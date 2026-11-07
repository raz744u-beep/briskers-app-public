-- Business conflicts are HTTP 409, never transaction serialization failures.
-- PostgREST 14 can retry a custom 40001 indefinitely (Supabase KB, 2026-11-04).
-- Exact definitions checked before replacement; CREATE OR REPLACE retains ACLs,
-- owner, security mode, search_path, validation and idempotency checks.
DO $repair$
DECLARE item record; signature_oid oid; definition text;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('public.briskers_add_document_discount(uuid,uuid,bigint,text,text,numeric,text,text)','ae6d115818d0763cc43e3f75fa84eab5','24b7230a99cbeba780ef6d2c669c459e'),
    ('public.briskers_add_document_line(uuid,uuid,bigint,text,numeric,numeric,numeric,text,uuid,text)','8968d305302650aeedffe1dae4a6987a','84ac71768860a329e0a40694b618a93f'),
    ('public.briskers_approve_appointment(uuid,uuid,bigint,timestamp with time zone,timestamp with time zone,uuid)','92814fbf862ef146674d8c4151f99d28','a60ab4319487bfab304170cd3c0a0722'),
    ('public.briskers_copy_document_line(uuid,uuid,bigint)','faea5fae58687a25d1997f12cd0fc5b8','64351876eb76c58a479d46b1943ba6c4'),
    ('public.briskers_delete_document_line(uuid,uuid,bigint)','4e931fa09b9a5f24906dcd318de20631','fa839af76d0baff5573c141c2f4c949d'),
    ('public.briskers_issue_document(uuid,uuid,bigint,date)','a253231c57c3be744c07d82750d0004b','36e9243581b69546a19cb5ff463b54aa'),
    ('public.briskers_mark_labor_earned(uuid,uuid,bigint,date)','c14bc8d5777cfdbc20e681c21ca7c45b','20fba1186ae9bb7515ca831ce6a0cb48'),
    ('public.briskers_move_document_line(uuid,uuid,bigint,text)','ff6dc6e06487372b4f0a8326d86d498c','719b2c3eeedfcc3ccff23dc2b11c9b97'),
    ('public.briskers_owner_force_reopen_invoice(uuid,uuid,bigint,text)','ba2d42f88e32e93977db60cf60059b3a','d100944125205f7bdfcab7cea85c8f13'),
    ('public.briskers_patch_document_note_template_v1(uuid,uuid,bigint,jsonb)','e28da9763e65a533aa552c293a426c95','10f3ed684cd46fc3c5e759ce9ccd646a'),
    ('public.briskers_save_expense_receipt_item_v1(uuid,uuid,uuid,bigint,text,text,numeric,numeric,numeric)','1970d33607f1ce767cad1f189112662f','e9874422946a62eba74f21b5fa7c7730'),
    ('public.briskers_save_invoice_mileage_out_v1(uuid,uuid,bigint,numeric)','44f09f4a10d01b323abfc42e464ccfdb','dc97ab2c93aa38b72c3e222e41f5cdbe'),
    ('public.briskers_sync_offline_appointment_cancel(uuid,uuid,uuid,bigint)','6b4b1dbbdd527a9946fbecb106c4cd48','543d1f11c6b714c8ce5f335afb2e6846'),
    ('public.briskers_sync_offline_appointment_delete(uuid,uuid,uuid,bigint)','1c230c1c891cf39dec671fed3e9db695','79c2bd8d20529c827f87d0862c05f76e'),
    ('public.briskers_sync_offline_appointment_edit(uuid,uuid,uuid,bigint,text,text,timestamp with time zone,timestamp with time zone,uuid)','d08db4ee9b53d5da5d1c299916ea45d0','e083527fa51f2ea850392f4a0a729849'),
    ('public.briskers_sync_offline_appointment_reassign(uuid,uuid,uuid,bigint,uuid,uuid,text,text,timestamp with time zone,timestamp with time zone,uuid)','8e17a00bc21b6cf3e859fddb4b235d6b','7cb02e959e31b067d0d799467828e9c1'),
    ('public.briskers_sync_recurring_bundle_v1(uuid,text,jsonb,jsonb)','7b77814e9133469ba629c6d9c39aeb38','70e728a2a43c75930b32dfa351c22490'),
    ('public.briskers_test_job_cleanup_execute_v1(uuid,uuid,text,text)','855277971f116832a06eefd7f135251a','2b1f0653170fbee66b6dad53defa8838'),
    ('public.briskers_update_document_claim_info(uuid,uuid,bigint,text,text)','3ea9eeeea3efb0c8000b811def9ce679','7a8a101ee443f4ba7e887af07910be71'),
    ('public.briskers_update_document_discount(uuid,uuid,bigint,text,text,numeric,text,text)','408f1e8038c6dd7994af416a028e159d','e87b466bc283baefacc940d6482b03aa'),
    ('public.briskers_update_document_header(uuid,uuid,bigint,uuid,uuid,date)','f34df8767e26a50817089c6efa3fee3a','4bfcbfc470ec183a0df2a8f28adbc5f3'),
    ('public.briskers_update_document_line(uuid,uuid,bigint,numeric,numeric,numeric,text)','30b3bdcf3dc873cdc117556d974b7305','d4b73129edf440b3adda2b23580e28a1'),
    ('public.briskers_update_document_line_v2(uuid,uuid,bigint,text,numeric,numeric,numeric,text,text)','780a6fdc0398dd76fd4cd1ce3da71cce','5f80e756d36380bf260a525fd61cfb49'),
    ('public.briskers_update_document_notes(uuid,uuid,bigint,text)','666540965084c3b4c5bbed4a106b12af','1702a4cc4191fdea24d77ff6233feaa6'),
    ('public.briskers_update_document_warranty(uuid,uuid,bigint,boolean,uuid,text,text,numeric,numeric)','5a2f9403697678dbb0a7a5d094e6c88b','11ceed963964f4d3d447363c68ec02cc'),
    ('public.briskers_update_invoice_tax_rate_v1(uuid,uuid,bigint,numeric,numeric)','762ffd7b74da3ad81f719f1673d61e24','01afdd4e185e79b481c04792208b64c3'),
    ('public.briskers_update_pending_invoice_payment_v2(uuid,uuid,numeric,uuid,date,bigint)','b75aef7867e4d5a2c69a9f6e3bac280b','9d8e10fd6b4ea1e32b195bf0c1425013')
  ) AS expected(signature,original_md5,patched_md5)
  LOOP
    signature_oid := to_regprocedure(item.signature);
    IF signature_oid IS NULL THEN
      RAISE EXCEPTION 'Missing reviewed function: %', item.signature;
    END IF;
    definition := pg_get_functiondef(signature_oid);
    IF md5(definition) = item.patched_md5 THEN CONTINUE; END IF;
    IF md5(definition) <> item.original_md5 THEN
      RAISE EXCEPTION 'Definition changed; re-review required: %', item.signature;
    END IF;
    EXECUTE replace(definition, '''40001''', '''PT409''');
    IF md5(pg_get_functiondef(signature_oid)) <> item.patched_md5 THEN
      RAISE EXCEPTION 'Unexpected patched definition: %', item.signature;
    END IF;
  END LOOP;
END
$repair$;

