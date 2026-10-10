-- Internal helper must not be callable directly by mobile identities.
REVOKE ALL ON FUNCTION briskers.restore_estimate_after_invoice_delete(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
