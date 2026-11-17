-- Keep the currently deployed function body and grants, including any incident
-- containment. Only permanent snapshot mismatches become HTTP 409.
DO $migration$
DECLARE
  fn regprocedure := to_regprocedure(
    'public.briskers_finalize_invoice_once_v1(uuid,uuid,uuid,jsonb)');
  definition text;
  message text;
  retry text;
  terminal text;
BEGIN
  IF fn IS NULL THEN RETURN; END IF;
  definition := pg_get_functiondef(fn);
  FOREACH message IN ARRAY ARRAY[
    'Invoice totals changed; review saved finalization',
    'Recorded payment changed; review saved finalization',
    'Recorded payment set changed; review saved finalization'
  ] LOOP
    retry := format('RAISE EXCEPTION %L USING ERRCODE=''40001'';', message);
    terminal := format('RAISE EXCEPTION %L USING ERRCODE=''PT409'';', message);
    IF strpos(definition, retry) > 0 THEN
      definition := replace(definition, retry, terminal);
    ELSIF strpos(definition, terminal) = 0 THEN
      RAISE EXCEPTION 'Unexpected deployed finalization conflict definition: %', message;
    END IF;
  END LOOP;
  EXECUTE definition;
END
$migration$;
