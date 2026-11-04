"""Run only against the ephemeral PostgreSQL CI service with synthetic records."""
import concurrent.futures
import json
import subprocess
from decimal import Decimal

B = '00000000-0000-0000-0000-000000000001'
R = '00000000-0000-0000-0000-000000000005'
ACTOR = '00000000-0000-0000-0000-000000000006'


def sql(statement, *, actor=ACTOR, business=B, success=True):
    setup = f"SET test.actor='{actor}'; SET test.business='{business}';\n"
    p = subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
                       input=setup + statement, text=True, capture_output=True)
    if success:
        assert p.returncode == 0, p.stderr
    else:
        assert p.returncode != 0, 'Expected rejection'
    return p.stdout.strip()


def literal(value):
    return "'" + json.dumps(value).replace("'", "''") + "'::jsonb"


rule = dict(id=R, business_id=B, direction='expense',
            account_id='00000000-0000-0000-0000-000000000002',
            category_id='00000000-0000-0000-0000-000000000003',
            vendor_id='00000000-0000-0000-0000-000000000004',
            amount_minor=10000, frequency='weekly', interval_count=1,
            next_date='2026-11-11', end_date=None, is_repeating=True,
            row_version=None, remarks='Synthetic')
occ = dict(id='local-recurring-example', business_id=B, direction='expense',
           account_id=rule['account_id'], category_id=rule['category_id'],
           vendor_id=rule['vendor_id'], amount_minor=10000, date='2026-11-04',
           recurring_rule_id=R, recurring_occurrence_date='2026-11-04',
           row_version=None, remarks='Synthetic')


def bundle(token, r=rule, rows=None, **kwargs):
    rows = [occ] if rows is None else rows
    return sql(f"SELECT public.briskers_sync_recurring_bundle_v1('{B}',"
               f"'{token}',{literal(r)},{literal(rows)});", **kwargs)


# Concurrent requests from two clients converge through the rule lock and index.
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
    first, second = list(executor.map(bundle, ['device-a', 'device-b']))
a, b = json.loads(first), json.loads(second)
assert a['occurrences'][0]['id'] == b['occurrences'][0]['id']
assert sql('SELECT count(*) FROM briskers.financial_transactions;') == '1'
assert sql('SELECT count(*) FROM briskers.expense_allocations;') == '1'
assert json.loads(bundle('device-a')) == a
bundle('device-a', r={**rule, 'remarks': 'changed request'}, success=False)

snapshot = json.loads(sql(f"SELECT public.briskers_recurring_recovery_v1('{B}');"))
assert snapshot['complete'] and snapshot['occurrence_count'] == 1
assert snapshot['rules'][0]['amount_minor'] == 10000
assert snapshot['occurrences'][0]['recurring_occurrence_date'] == '2026-11-04'

# Stale conflicting local edits do not mutate the schedule or existing expense.
bundle('stale', r={**rule, 'amount_minor': 12000}, success=False)
assert Decimal(sql('SELECT amount FROM briskers.financial_transactions;')) == -100

current_rule = a['rule']
current_occ = a['occurrences'][0]
corrected = json.loads(bundle('correct', r=current_rule,
                             rows=[{**current_occ, 'amount_minor': 12000}]))
assert corrected['occurrences'][0]['amount_minor'] == 12000
assert Decimal(sql('SELECT amount FROM briskers.expense_allocations;')) == 120

# Even after the rule UPDATE, a conflicting occurrence aborts the entire bundle.
bundle('rollback', r={**current_rule, 'next_date': '2026-11-18'},
       rows=[{**current_occ, 'amount_minor': 13000}], success=False)
assert sql('SELECT next_date FROM briskers.recurring_transactions;') == '2026-11-11'

# Read-only snapshot cannot schedule overdue entries.
sql(f"UPDATE briskers.recurring_transactions SET next_date='2026-01-01',is_repeating=false;")
snapshot = json.loads(sql(f"SELECT public.briskers_recurring_recovery_v1('{B}');"))
assert snapshot['rules'][0]['is_repeating'] is False
assert sql('SELECT count(*) FROM briskers.financial_transactions;') == '1'

# Authentication, business isolation, function grants and private replay store.
sql(f"SELECT public.briskers_recurring_recovery_v1('{B}');", actor='', success=False)
sql("SELECT public.briskers_recurring_recovery_v1('00000000-0000-0000-0000-000000000099');", success=False)
bundle('unauthenticated', actor='', success=False)
assert sql("SELECT has_function_privilege('anon','public.briskers_sync_recurring_bundle_v1(uuid,text,jsonb,jsonb)','EXECUTE');") == 'f'
assert sql("SELECT has_table_privilege('authenticated','briskers.recurring_sync_receipts_v1','SELECT');") == 'f'
print('PostgreSQL recurrence recovery, concurrency, retries, CAS, rollback and scope checks passed')
