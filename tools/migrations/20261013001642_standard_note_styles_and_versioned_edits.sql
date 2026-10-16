-- Standard-note styles and optimistic, field-level edits.
-- Non-destructive: no invoice/job/customer data is modified. Existing template
-- create/save RPC signatures remain unchanged; older clients remain compatible.
BEGIN;

ALTER TABLE briskers.document_note_templates
  ADD COLUMN IF NOT EXISTS color_hex text NOT NULL DEFAULT '#1565C0'
    CHECK (color_hex ~ '^#[0-9A-Fa-f]{6}$');

-- Case-insensitive uniqueness matches the mobile/offline identity rules.
-- Preflight read-only metadata check on 2026-10-13 found no normalized duplicate
-- groups. If one appears before deployment this fails atomically; do not delete
-- or rewrite any notes to force this index through.
CREATE UNIQUE INDEX IF NOT EXISTS document_note_templates_business_normalized_name_key
  ON briskers.document_note_templates (business_id, lower(btrim(name)));

CREATE OR REPLACE FUNCTION public.briskers_document_note_templates(
  p_business_id uuid, p_include_inactive boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM briskers.require_permission(p_business_id, 'invoices.read');
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'name', t.name, 'body', t.body,
    'template_type', t.template_type,
    'show_in_quick_list', t.show_in_quick_list, 'active', t.active,
    'sort_order', t.sort_order, 'row_version', t.row_version,
    'color_hex', t.color_hex
  ) ORDER BY (lower(btrim(t.name)) = 'general'), t.sort_order, lower(t.name)), '[]'::jsonb)
  INTO v
  FROM briskers.document_note_templates t
  WHERE t.business_id = p_business_id
    AND (p_include_inactive OR t.active);
  RETURN v;
END
$function$;

-- Keep the General identity stable even when an older settings screen calls
-- the legacy save RPC. Case/whitespace normalization is still harmless.
CREATE OR REPLACE FUNCTION briskers.keep_general_note_name()
RETURNS trigger
LANGUAGE plpgsql SET search_path = ''
AS $function$
BEGIN
  IF lower(btrim(OLD.name)) = 'general'
      AND lower(btrim(NEW.name)) <> 'general' THEN
    RAISE EXCEPTION 'General must keep its name and stay last'
      USING errcode = '22023';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS keep_general_note_name ON briskers.document_note_templates;
CREATE TRIGGER keep_general_note_name
  BEFORE UPDATE OF name ON briskers.document_note_templates
  FOR EACH ROW EXECUTE FUNCTION briskers.keep_general_note_name();

CREATE OR REPLACE FUNCTION public.briskers_patch_document_note_template_v1(
  p_business_id uuid,
  p_template_id uuid,
  p_expected_version bigint,
  p_patch jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v briskers.document_note_templates%ROWTYPE;
  v_name text;
  v_body text;
  v_color text;
  v_sort integer;
BEGIN
  IF auth.uid() IS NULL OR NOT coalesce(briskers.is_owner(p_business_id), false) THEN
    RAISE EXCEPTION 'Owner access required' USING errcode = '42501';
  END IF;
  IF p_patch IS NULL OR jsonb_typeof(p_patch) <> 'object' THEN
    RAISE EXCEPTION 'A standard note patch is required' USING errcode = '22023';
  END IF;
  IF (p_patch - ARRAY['name', 'body', 'color_hex', 'sort_order']) <> '{}'::jsonb THEN
    RAISE EXCEPTION 'Unsupported standard note fields' USING errcode = '22023';
  END IF;
  SELECT t.* INTO v
    FROM briskers.document_note_templates t
    WHERE t.id = p_template_id AND t.business_id = p_business_id
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Note template not found' USING errcode = 'P0002';
  END IF;
  IF p_expected_version IS NULL OR v.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Standard note changed elsewhere; refresh before saving'
      USING errcode = '40001';
  END IF;
  IF NOT v.active THEN
    RAISE EXCEPTION 'Standard note is inactive' USING errcode = '22023';
  END IF;
  v_name := CASE WHEN p_patch ? 'name' THEN btrim(p_patch->>'name') ELSE v.name END;
  v_body := CASE WHEN p_patch ? 'body' THEN btrim(p_patch->>'body') ELSE v.body END;
  v_color := CASE WHEN p_patch ? 'color_hex' THEN upper(btrim(p_patch->>'color_hex')) ELSE v.color_hex END;
  v_sort := CASE WHEN p_patch ? 'sort_order' THEN (p_patch->>'sort_order')::integer ELSE v.sort_order END;
  IF coalesce(v_name, '') = '' OR coalesce(v_body, '') = '' THEN
    RAISE EXCEPTION 'Name and note text are required' USING errcode = '22023';
  END IF;
  IF v_color IS NULL OR v_color !~ '^#[0-9A-F]{6}$' OR v_sort IS NULL THEN
    RAISE EXCEPTION 'Invalid standard note color or order' USING errcode = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM briskers.document_note_templates t
      WHERE t.business_id = p_business_id AND t.id <> p_template_id
        AND lower(btrim(t.name)) = lower(v_name)) THEN
    RAISE EXCEPTION 'A standard note already has this name' USING errcode = '23505';
  END IF;
  UPDATE briskers.document_note_templates t
  SET name = v_name, body = v_body, color_hex = v_color,
      sort_order = v_sort, updated_at = clock_timestamp(),
      row_version = t.row_version + 1
  WHERE t.business_id = p_business_id AND t.id = p_template_id
  RETURNING t.* INTO v;
  RETURN jsonb_build_object(
    'id', v.id, 'name', v.name, 'body', v.body,
    'template_type', v.template_type,
    'show_in_quick_list', v.show_in_quick_list, 'active', v.active,
    'sort_order', v.sort_order, 'row_version', v.row_version,
    'color_hex', v.color_hex
  );
END
$function$;

REVOKE ALL ON FUNCTION briskers.keep_general_note_name() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.briskers_patch_document_note_template_v1(uuid, uuid, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_patch_document_note_template_v1(uuid, uuid, bigint, jsonb) TO authenticated;

COMMIT;
