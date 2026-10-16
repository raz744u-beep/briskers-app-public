"""Executes the actual Dart SQL templates with SQLite, not a Dart/Flutter test.
This catches SQL/JSON1 trigger syntax and basic fence regressions when Flutter
is unavailable. Exact-source Flutter tests remain required before release.
"""
import json
import re
import sqlite3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'lib/services/local_job_deletion_v3.dart').read_text()
schema = (root / 'lib/local/briskers_local_database.dart').read_text()
db = sqlite3.connect(':memory:')
def snake(value):
    return re.sub(r'(?<!^)(?=[A-Z])', '_', value).lower()
for name, body in re.findall(r'class (\w+) extends Table \{(.*?)\n\}', schema, re.S):
    columns = re.findall(r'(?:Text|Int|Bool|Real|DateTime)Column get (\w+) =>', body)
    db.execute(f'CREATE TABLE {snake(name)} ({", ".join(snake(c)+" TEXT" for c in columns)})')

ensure = source[source.index('static Future<void> ensureSchema'):source.index('static Future<void> setPendingIntent')]
templates = re.findall(r"customStatement\('''(.*?)'''\)", ensure, re.S)
for sql in templates:
    if '$' not in sql:
        db.execute(sql)
for sql in re.findall(r'customStatement\("(CREATE TRIGGER.*?)"\)', ensure):
    db.execute(sql)

def read_refs(name):
    raw = ensure.split('final '+name+' = <String, String>{', 1)[1].split('\n      };', 1)[0]
    result = {}
    def matches(kind, field):
        return f"(e.entity_kind='{kind}' AND e.entity_id={field})"
    for line in raw.splitlines():
        line = line.strip()
        if not line: continue
        key, value = re.match(r"'([^']+)': (.*),$", line).groups()
        if value.startswith('_matches('):
            value = matches(*re.match(r"_matches\('([^']+)', '([^']+)'\)", value).groups())
        else:
            value = value[1:-1]
            value = re.sub(r"\$\{_matches\('([^']+)', '([^']+)'\)\}", lambda m: matches(*m.groups()), value)
        result[key] = value
    return result
refs = read_refs('refs')
old_refs = read_refs('oldRefs')

row_template = next(t for t in templates if 'deletion_v3_${entry.key}' in t)
for table, ref in refs.items():
    for action in ['INSERT', 'UPDATE']:
        old = (f' OR EXISTS(SELECT 1 FROM local_job_deletion_v3_fences e '
               f"WHERE e.business_id=OLD.business_id AND ({old_refs[table]}))") if action == 'UPDATE' else ''
        sql = row_template.replace('${entry.key}', table).replace('${action.toLowerCase()}', action.lower())
        sql = sql.replace('$action', action).replace('${entry.value}', ref).replace('$old', old)
        assert '$' not in sql, sql
        db.execute(sql)
payload_template = next(t for t in templates if 'deletion_v3_${table}' in t)
for table in ['sync_outbox', 'local_financial_cache']:
    for action in ['INSERT', 'UPDATE']:
        identity = 'e.entity_id=NEW.entity_id OR' if table == 'sync_outbox' else "(e.entity_kind='transaction' AND NEW.cache_key='transaction_detail_'||e.entity_id) OR"
        sql = payload_template.replace('${table}', table).replace('$table', table)
        sql = sql.replace('${action.toLowerCase()}', action.lower()).replace('$action', action).replace('$identity', identity)
        raw_operation = source.split('static const _outboxOperationSql = ',1)[1].split(';',1)[0]
        operation_sql = ''.join(re.findall(r'\"(.*?)\"', raw_operation)).replace('\\$', '$')
        sql = sql.replace('$operationCheck', operation_sql if table == 'sync_outbox' else '0')
        assert '${' not in sql, sql
        db.execute(sql)

def blocked(sql, values=()):
    try:
        db.execute(sql, values)
    except sqlite3.IntegrityError:
        return
    raise AssertionError('Unsafe write accepted: '+sql)
for kind, id in [('job','j'),('invoice','i'),('estimate','e'),('payment','p'),('transaction','t'),('operation','invoice_payment/key')]:
    db.execute('INSERT INTO local_job_deletion_v3_entities VALUES (?,?,?,?,?)', ['b','j','op',kind,id])
for id, kind in [('i','invoice'),('e','estimate')]:
    blocked('INSERT INTO local_documents (business_id,id,kind) VALUES (?,?,?)', ['b',id,kind])
for payload in [{'payment_id':'p'}, {'transaction_id':'t'}]:
    blocked('INSERT INTO sync_outbox (business_id,entity_id,payload_json) VALUES (?,?,?)', ['b','unrelated',json.dumps(payload)])
blocked('INSERT INTO sync_outbox (business_id,entity_type,entity_id,payload_json) VALUES (?,?,?,?)', ['b','invoice_payment_received','unrelated',json.dumps({'operation_id':'key'})])
db.execute('INSERT INTO sync_outbox (business_id,entity_type,entity_id,payload_json) VALUES (?,?,?,?)', ['b','other_namespace','unrelated',json.dumps({'operation_id':'key'})])
blocked('INSERT INTO sync_outbox (business_id,entity_id,payload_json) VALUES (?,?,?)', ['b','unrelated','bad-json'])
blocked('INSERT INTO local_financial_cache (business_id,cache_key,payload_json) VALUES (?,?,?)', ['b','detail',json.dumps({'payments':[{'id':'p'}]})])
blocked("DELETE FROM local_job_deletion_v3_entities WHERE entity_id='i'")
blocked('INSERT OR REPLACE INTO local_job_deletion_v3_entities VALUES (?,?,?,?,?)', ['b','other','other','invoice','i'])
db.execute('INSERT INTO local_documents (business_id,id,kind) VALUES (?,?,?)', ['b','keep','invoice'])
db.execute('INSERT INTO sync_outbox (business_id,entity_id,payload_json) VALUES (?,?,?)', ['b','keep',json.dumps({'memo':'unrelated'})])
db.execute('INSERT INTO local_job_deletion_v3_pending VALUES (?,?,?,?,?)', ['b','next','pending','job','next'])
blocked('INSERT INTO local_jobs (business_id,id) VALUES (?,?)', ['b','next'])
db.execute("DELETE FROM local_job_deletion_v3_pending WHERE operation_id='pending'")
db.execute('INSERT INTO local_jobs (business_id,id) VALUES (?,?)', ['b','next'])
print(f'PASS: {len(refs)*2+4+6} exact-source generated SQLite trigger/schema checks; INSERT/UPDATE templates parse; late UUID/payment/operation replay rejected; unrelated work preserved; reversible pending fences checked.')
