"""Execute offline-cancellation SQL templates against SQLite, not Flutter.
Flutter tests still have to run in the exact-source app CI.
"""
import re, sqlite3
from pathlib import Path
root = Path(__file__).resolve().parents[1]
s = (root / 'lib/services/offline_job_purge.dart').read_text()
db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE sync_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT,business_id TEXT,entity_type TEXT,entity_id TEXT,operation TEXT,payload_json TEXT,state TEXT DEFAULT "pending",attempt_count INTEGER DEFAULT 0,last_attempt_at INTEGER)')
ensure = s[s.index('static Future<void> ensureSchema'):s.index('static Future<void> recordNewIntent')]
for sql in re.findall(r"customStatement\('''(.*?)'''\)", ensure, re.S):
    assert '$' not in sql, sql
    db.execute(sql)
for table in ['local_offline_job_purge_entities','local_offline_dispatch_proof','local_offline_dispatch_ids','local_offline_authored_ids']:
    db.execute(f"CREATE TRIGGER {table}_immutable_delete BEFORE DELETE ON {table} BEGIN SELECT RAISE(ABORT,'Cancellation and dispatch identities are permanent'); END")
def blocked(sql,args=()):
    try: db.execute(sql,args)
    except sqlite3.IntegrityError: return
    raise AssertionError('Unsafe write accepted: '+sql)
db.execute("INSERT INTO sync_outbox(business_id,entity_id) VALUES ('b','job')")
assert db.execute('SELECT dispatched FROM local_offline_dispatch_proof').fetchone()[0] == 0
db.execute("UPDATE sync_outbox SET state='inflight',last_attempt_at=1 WHERE id=1")
assert db.execute('SELECT dispatched FROM local_offline_dispatch_proof').fetchone()[0] == 1
db.execute("UPDATE sync_outbox SET state='pending',attempt_count=0,last_attempt_at=NULL WHERE id=1")
assert db.execute('SELECT dispatched FROM local_offline_dispatch_proof').fetchone()[0] == 1
blocked('UPDATE local_offline_dispatch_proof SET dispatched=0')
blocked("INSERT OR REPLACE INTO local_offline_dispatch_proof VALUES ('b',1,0)")
blocked('DELETE FROM local_offline_dispatch_proof')
blocked("UPDATE local_offline_dispatch_proof SET business_id='other'")
db.execute("INSERT INTO local_offline_job_purge_entities VALUES ('b','job','op','job','job')")
blocked("UPDATE local_offline_job_purge_entities SET job_id='other'")
blocked("INSERT OR REPLACE INTO local_offline_job_purge_entities VALUES ('b','other','other','job','job')")
blocked('DELETE FROM local_offline_job_purge_entities')
# Restoring a queue never creates original-author provenance.
db.execute("INSERT INTO sync_outbox(business_id,entity_id) VALUES ('b','restored')")
assert db.execute('SELECT count(*) FROM local_offline_authored_ids').fetchone()[0] == 0
# Imported evidence starts unsafe even if counters are reset later.
db.execute("INSERT INTO sync_outbox(business_id,entity_id,attempt_count) VALUES ('b','attempted',1)")
db.execute('UPDATE sync_outbox SET attempt_count=0 WHERE id=3')
assert db.execute('SELECT dispatched FROM local_offline_dispatch_proof WHERE outbox_id=3').fetchone()[0] == 1
print('PASS: exact-source offline schema/triggers; monotonic claims, reset/replace/delete rejection, provenance not backfilled, permanent cancellation markers.')
