"""Guard indexed estimate conversion reads against full JSON cache materialization."""
import json
from pathlib import Path
import re
import sqlite3
import unittest


class EstimateProjectionQueryTest(unittest.TestCase):
    def test_scoped_conversion_uses_cache_keys_and_preserves_both_snapshot_sources(self):
        source = (Path(__file__).resolve().parents[2] /
                  'lib/services/local_estimate_conversion.dart').read_text()
        section = source.split('final records = await db.customSelect(', 1)[1].split('variables:', 1)[0]
        query = ''.join(json.loads(value.replace('\\$', '$'))
                        for value in re.findall(r'"(?:\\.|[^"\\])*"', section))
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript('''
            CREATE TABLE local_documents(id TEXT,business_id TEXT,kind TEXT,
                converted INTEGER,document_number TEXT,document_date TEXT);
            CREATE TABLE local_document_details(cache_key TEXT PRIMARY KEY,payload_json TEXT);
            CREATE TABLE recovery_document_cache(business_id TEXT,document_id TEXT,
                payload_json TEXT,PRIMARY KEY(business_id,document_id));
            CREATE TABLE local_document_detail_deleted(cache_key TEXT PRIMARY KEY);
        ''')
        for business in ['shop', 'other']:
            for doc_id, kind in [('estimate', 'estimate'), ('invoice', 'invoice')]:
                db.execute('INSERT INTO local_documents VALUES(?,?,?,0,?,?)',
                           (doc_id, business, kind, doc_id, '2026-11-19'))
                payload = {'id': doc_id, 'kind': kind, 'business_id': business,
                           'lines': [{'description': 'large work record' * 1000}]}
                if kind == 'invoice':
                    payload['source_estimate_id'] = 'estimate'
                raw = json.dumps(payload)
                db.execute('INSERT INTO local_document_details VALUES(?,?)',
                           (f'briskers_document_detail_{business}_{doc_id}', raw))
                db.execute('INSERT INTO recovery_document_cache VALUES(?,?,?)',
                           (business, doc_id, raw))
        args = ('shop', '["estimate"]', '["estimate"]')
        rows = db.execute(query, args).fetchall()
        self.assertEqual(len(rows), 4)  # Both independent snapshots remain evidence.
        self.assertEqual([r[-1] for r in rows if r[1] == 'invoice'], ['estimate', 'estimate'])
        self.assertTrue(all(json.loads(r[-2])['business_id'] == 'shop'
                            for r in rows if r[-2] is not None))
        plan = [r[3] for r in db.execute('EXPLAIN QUERY PLAN ' + query, args)]
        self.assertFalse(any('SCAN local_document_details' in step or
                             'SCAN recovery_document_cache' in step for step in plan), plan)
        self.assertTrue(any('SEARCH c USING INDEX' in step for step in plan), plan)
        db.execute("INSERT INTO local_document_detail_deleted VALUES('briskers_document_detail_shop_invoice')")
        self.assertEqual([r[1] for r in db.execute(query, args)], ['estimate', 'estimate'])


if __name__ == '__main__':
    unittest.main()
