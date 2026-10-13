-- Group reusable invoice notes without changing their saved text.
-- Both old and new clients remain compatible: legacy create defaults to Service;
-- newer clients set category_key by the owner-only optimistic patch.
BEGIN;
ALTER TABLE briskers.document_note_templates
  ADD COLUMN IF NOT EXISTS category_key text NOT NULL DEFAULT 'service';
ALTER TABLE briskers.document_note_templates
  DROP CONSTRAINT IF EXISTS document_note_templates_category_key_check;
ALTER TABLE briskers.document_note_templates
  ADD CONSTRAINT document_note_templates_category_key_check
  CHECK (category_key IN ('service','warranty','inspection','advisory','general'));

-- Metadata-only classification for historical notes. No name/body edits.
UPDATE briskers.document_note_templates
SET category_key = CASE
  WHEN lower(btrim(name))='general' OR lower(name) LIKE '%thank%' THEN 'general'
  WHEN lower(name) LIKE '%warranty%' THEN 'warranty'
  WHEN lower(name) LIKE '%inspect%' THEN 'inspection'
  WHEN lower(name) LIKE '%advis%' OR lower(name) LIKE '%warning%' THEN 'advisory'
  ELSE 'service'
END
WHERE category_key='service';

DO $migration$
DECLARE list_fn text; patch_fn text;
BEGIN
 SELECT pg_get_functiondef(p.oid) INTO list_fn
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='briskers_document_note_templates'
 ORDER BY p.oid LIMIT 1;
 IF list_fn IS NULL OR position('''color_hex'', t.color_hex' in list_fn)=0
 THEN RAISE EXCEPTION 'Unexpected list note templates RPC'; END IF;
 list_fn := replace(list_fn, '''color_hex'', t.color_hex',
   '''color_hex'', t.color_hex, ''category_key'', t.category_key');
 EXECUTE list_fn;

 SELECT pg_get_functiondef(p.oid) INTO patch_fn
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='briskers_patch_document_note_template_v1'
 ORDER BY p.oid LIMIT 1;
 IF patch_fn IS NULL
   OR position('v_sort integer;' in patch_fn)=0
   OR position('''color_hex'', v.color_hex' in patch_fn)=0
   OR position('''name'', ''body'', ''color_hex'', ''sort_order''' in patch_fn)=0
 THEN RAISE EXCEPTION 'Unexpected patch note template RPC'; END IF;
 patch_fn := replace(patch_fn, 'v_sort integer;',
   'v_sort integer; v_category text;');
 patch_fn := replace(patch_fn,
   '''name'', ''body'', ''color_hex'', ''sort_order''',
   '''name'', ''body'', ''color_hex'', ''sort_order'', ''category_key''');
 patch_fn := replace(patch_fn,
   '  IF coalesce(v_name, '''')',
   '  v_category := CASE WHEN p_patch ? ''category_key'' THEN lower(btrim(p_patch->>''category_key'')) ELSE v.category_key END;' || E'\n' ||
   '  IF coalesce(v_name, '''')');
 patch_fn := replace(patch_fn,
   'OR v_sort IS NULL THEN',
   'OR v_sort IS NULL OR v_category NOT IN (''service'',''warranty'',''inspection'',''advisory'',''general'') THEN');
 patch_fn := replace(patch_fn,
   'SET name = v_name, body = v_body, color_hex = v_color,',
   'SET name = v_name, body = v_body, color_hex = v_color, category_key = v_category,');
 patch_fn := replace(patch_fn,
   '''color_hex'', v.color_hex',
   '''color_hex'', v.color_hex, ''category_key'', v.category_key');
 EXECUTE patch_fn;
END $migration$;
COMMIT;
