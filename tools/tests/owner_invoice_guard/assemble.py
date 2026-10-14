#!/usr/bin/env python3
"""Assemble public synthetic SQL without reading or embedding private RPC bodies.

Only the in-memory migration copy receives fixture-specific SHA-256 values.
The production migration on disk is never edited and retains its live allowlist.
"""
from pathlib import Path
import hashlib
import re

here = Path(__file__).resolve().parent
migration = here.parents[2] / 'supabase/migrations/20261014064717_owner_invoice_finalization_guard.sql'
sql = migration.read_text()
fixtures = (here / 'synthetic_rpcs.sql').read_text()
guard = (
    "  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN\n"
    "    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';\n"
    "  END IF;\n"
)
functions = re.findall(
    r'CREATE OR REPLACE FUNCTION public\.(\w+)\(.*?AS \$function\$(.*?)\$function\$',
    fixtures, re.S,
)
assert len(functions) == 2
for name, body in functions:
    assert body.count('begin\n') == 1
    patched = body.replace('begin\n', 'begin\n' + guard, 1)
    original_hash = hashlib.sha256(body.encode()).hexdigest()
    guarded_hash = hashlib.sha256(patched.encode()).hexdigest()
    pattern = r"\('public\." + re.escape(name) + r"\(uuid,uuid\)', '[0-9a-f]{64}', '[0-9a-f]{64}'\)"
    replacement = f"('public.{name}(uuid,uuid)', '{original_hash}', '{guarded_hash}')"
    sql, replacements = re.subn(pattern, lambda _: replacement, sql)
    assert replacements == 1, f'Unexpected migration allowlist for {name}'
assert '$test_migration_source$' not in sql
print('-- SYNTHETIC TEST ONLY: hashes below match synthetic fixtures, not live RPCs.')
print('BEGIN;')
print((here / 'fixture.sql').read_text())
print(fixtures)
print('CREATE FUNCTION owner_guard_test.apply_migration() RETURNS void LANGUAGE plpgsql AS $test_apply$')
print('BEGIN EXECUTE $test_migration_source$' + sql + '$test_migration_source$; END; $test_apply$;')
print((here / 'checks.sql').read_text())
print((here / 'drift_checks.sql').read_text())
print('ROLLBACK;')
