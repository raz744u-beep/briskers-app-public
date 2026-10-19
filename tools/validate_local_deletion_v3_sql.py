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
dirty_template = next(t for t in templates if 'deletion_v3_scope_dirty_${entry.key}' in t)
for table in refs:
    db.execute(dirty_template.replace('${entry.key}',table).replace('${oldRefs[entry.key]}',old_refs[table]))
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
        sql = sql.replace('$scopeFilter', '' if table == 'sync_outbox' else " AND (e.operation_id<>'' OR EXISTS(SELECT 1 FROM local_job_deletion_v3_scope_entities s WHERE s.business_id=e.business_id AND s.entity_kind=e.entity_kind AND s.entity_id=e.entity_id AND s.dirty=1))")
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

# Scope quarantine is reversible only for replaceable identities. Retained
# dirty children cannot disappear through generic sync's DELETE-before-replace.
db.execute("INSERT INTO local_job_visits(id,business_id,job_id) VALUES ('dirty-visit','scope','job')")
db.execute("INSERT INTO local_job_deletion_v3_scope_entities VALUES ('scope','job_visit','dirty-visit',1,1)")
blocked("DELETE FROM local_job_visits WHERE business_id='scope' AND id='dirty-visit'")
db.execute("DELETE FROM local_job_deletion_v3_scope_entities WHERE business_id='scope' AND dirty=0")
assert db.execute("SELECT COUNT(*) FROM local_job_deletion_v3_scope_entities WHERE business_id='scope'").fetchone()[0] == 1
db.execute("INSERT INTO local_documents(id,business_id,kind) VALUES ('clean-invoice','scope','invoice')")
db.execute("INSERT INTO local_job_deletion_v3_scope_entities VALUES ('scope','invoice','clean-invoice',1,0)")
blocked("UPDATE local_documents SET kind='invoice' WHERE business_id='scope' AND id='clean-invoice'")
db.execute("DELETE FROM local_job_deletion_v3_scope_entities WHERE business_id='scope' AND entity_id='clean-invoice' AND dirty=0")
db.execute("UPDATE local_documents SET kind='invoice' WHERE business_id='scope' AND id='clean-invoice'")
db.execute("INSERT INTO local_financial_cache(business_id,cache_key,payload_json) VALUES ('scope','old','{}')")
db.execute("INSERT INTO local_job_deletion_v3_cache_scope VALUES ('scope','financial:old',0,1)")
blocked("DELETE FROM local_financial_cache WHERE business_id='scope' AND cache_key='old'")
print('PASS: 5 additional exact-source scope checks; dirty child/cache DELETE blocked; clean identity requires explicit release; dirty release refused.')
blocked("INSERT OR REPLACE INTO local_financial_cache(business_id,cache_key,payload_json) VALUES ('scope','old','{}')")
blocked("UPDATE local_financial_cache SET cache_key='new',payload_json='{}' WHERE business_id='scope' AND cache_key='old'")
print('PASS: 2 dirty financial-key overwrite checks; REPLACE and rename/update cannot erase key-only unknown work.')
db.execute("INSERT INTO sync_outbox(id,business_id,entity_type,entity_id,payload_json) VALUES (999,'scope','unknown','unrelated','{}')")
db.execute("INSERT INTO local_job_deletion_v3_scope_outbox VALUES ('scope',999)")
blocked("DELETE FROM sync_outbox WHERE id=999")
blocked("INSERT OR REPLACE INTO sync_outbox(id,business_id,entity_type,entity_id,payload_json) VALUES (999,'scope','other','different','{}')")
print('PASS: 2 scope-quarantined outbox checks; DELETE and REPLACE preserve original pending work.')

repository_source = (root / 'lib/services/local_job_repository.dart').read_text()
def child_sql(match):
    alias, kind, column = match.groups()
    kind = kind[1:-1]
    column = column or 'id'
    return (f'NOT EXISTS(SELECT 1 FROM local_job_deletion_v3_fences hidden '
            f'WHERE hidden.business_id={alias}.business_id AND hidden.entity_kind={kind} '
            f'AND hidden.entity_id={alias}.{column})')
def projection(name):
    raw = repository_source.split('static final '+name+' = """',1)[1].split('""";',1)[0]
    raw = re.sub(r'''\$\{_visibleChildSql\('([^']+)', ("[^"]+"|'[^']+')(?:, idColumn: '([^']+)')?\)\}''', child_sql, raw)
    return raw.replace('\\$', '$')
db.execute("INSERT INTO local_jobs(id,business_id,title,created_at,server_updated_at) VALUES ('root','activity','Fresh root',0,0)")
db.execute("INSERT INTO local_findings(id,business_id,found_job_id,created_at,server_updated_at,resolved_at) VALUES ('oldfinding','activity','root',123,123,123)")
activity_sql = f"SELECT {projection('_jobActivitySql')} FROM local_jobs j WHERE business_id='activity'"
assert int(db.execute(activity_sql).fetchone()[0]) == 123
db.execute("INSERT INTO local_job_deletion_v3_scope_entities VALUES ('activity','finding','oldfinding',1,0)")
assert int(db.execute(activity_sql).fetchone()[0]) == 0
db.execute(f"SELECT {projection('_jobDateSql')} FROM local_jobs j WHERE business_id='activity'").fetchall()
print('PASS: 3 actual job projection SQL checks; hidden child activity excluded and historical-date query parses.')

# Independent document authorization must not expose or authorize its parent.
# A scope-only parent does not block a clean, explicitly released document;
# irreversible deletion, pending consent, and local cancellation still do.
db.execute("INSERT INTO local_job_deletion_v3_scope_entities VALUES ('scope','job','hidden-parent',1,0)")
db.execute("UPDATE local_documents SET job_id='hidden-parent',status='fresh' WHERE business_id='scope' AND id='clean-invoice'")
assert db.execute("SELECT status FROM local_documents WHERE business_id='scope' AND id='clean-invoice'").fetchone()[0] == 'fresh'
assert db.execute("SELECT COUNT(*) FROM local_job_deletion_v3_scope_entities WHERE business_id='scope' AND entity_id='hidden-parent'").fetchone()[0] == 1
blocked("INSERT INTO local_documents(id,business_id,job_id,kind) VALUES ('new-doc','b','j','invoice')")
db.execute("INSERT INTO local_job_deletion_v3_pending VALUES ('pending-parent','root','op','job','root')")
blocked("INSERT INTO local_documents(id,business_id,job_id,kind) VALUES ('new-doc','pending-parent','root','invoice')")
db.execute("INSERT INTO local_offline_job_purge_entities VALUES ('cancelled-parent','root','op','job','root')")
blocked("INSERT INTO local_documents(id,business_id,job_id,kind) VALUES ('new-doc','cancelled-parent','root','invoice')")
for table, root_id in [('local_job_deletion_v3_entities','deleted-parent'),
                       ('local_job_deletion_v3_pending','pending-parent'),
                       ('local_offline_job_purge_entities','cancelled-parent')]:
    db.execute(f'INSERT INTO {table} VALUES (?,?,?,?,?)', ['scope',root_id,'op-'+root_id,'job',root_id])
    blocked("UPDATE local_documents SET job_id=? WHERE business_id='scope' AND id='clean-invoice'", [root_id])
print('PASS: 8 independent document/hidden-parent checks; refreshed document allowed, parent hidden, permanent/pending/local-cancel parent INSERT and UPDATE blocked.')

# Payment edit history is a distinct, server-confirmed identity. A stale
# financial response may contain only that audit UUID, without its payment or
# Job ID, so exercise the real JSON1 fences rather than assuming parent matches.
audit_id = '00000000-0000-4000-8000-000000000099'
db.execute('INSERT INTO local_job_deletion_v3_entities VALUES (?,?,?,?,?)',
           ['audit-scope', 'synthetic-job', 'synthetic-op', 'payment_edit_audit', audit_id])
audit_payload = json.dumps({'edit_history': [{'audit_id': audit_id}]})
for table, key in [('sync_outbox', 'entity_id'), ('local_financial_cache', 'cache_key')]:
    blocked(f'INSERT INTO {table}(business_id,{key},payload_json) VALUES (?,?,?)',
            ['audit-scope', 'stale-audit', audit_payload])
    db.execute(f'INSERT INTO {table}(business_id,{key},payload_json) VALUES (?,?,?)',
               ['audit-scope', 'unrelated-audit', '{}'])
    blocked(f'UPDATE {table} SET payload_json=? WHERE business_id=? AND {key}=?',
            [audit_payload, 'audit-scope', 'unrelated-audit'])
    # Tenant isolation: the same reference in another business is not fenced.
    db.execute(f'INSERT INTO {table}(business_id,{key},payload_json) VALUES (?,?,?)',
               ['audit-other', 'other-business-audit', audit_payload])
    assert db.execute(f'SELECT payload_json FROM {table} WHERE business_id=? AND {key}=?',
                      ['audit-scope', 'unrelated-audit']).fetchone()[0] == '{}'
    assert db.execute(f'SELECT payload_json FROM {table} WHERE business_id=? AND {key}=?',
                      ['audit-other', 'other-business-audit']).fetchone()[0] == audit_payload
assert db.execute('SELECT entity_kind FROM local_job_deletion_v3_fences '
                  'WHERE business_id=? AND entity_id=?',
                  ['audit-scope', audit_id]).fetchall() == [('payment_edit_audit',)]
blocked('UPDATE local_job_deletion_v3_entities SET entity_kind=? '
        'WHERE business_id=? AND entity_id=?', ['payment', 'audit-scope', audit_id])
blocked('DELETE FROM local_job_deletion_v3_entities WHERE business_id=? AND entity_id=?',
        ['audit-scope', audit_id])
print('PASS: 11 payment-edit audit checks; nested audit-only INSERT/UPDATE replay blocked, '
      'unrelated work and other businesses preserved, distinct audit identity immutable.')

