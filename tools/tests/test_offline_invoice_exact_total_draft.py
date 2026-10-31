from pathlib import Path
import unittest

SQL = Path("tools/recovery/offline_invoice_exact_total_v2_DRAFT.sql").read_text()

class ExactOfflineInvoiceRecoveryContract(unittest.TestCase):
    def test_new_api_is_versioned_and_permission_checked(self):
        self.assertIn("briskers_sync_offline_quick_invoice_v2(", SQL)
        self.assertIn("briskers.require_permission(p_business_id,'invoices.create')", SQL)
        self.assertIn("briskers.require_permission(p_business_id,'jobs.create')", SQL)
        self.assertIn("REVOKE ALL ON FUNCTION public.briskers_sync_offline_quick_invoice_v2(", SQL)
        self.assertIn("TO authenticated", SQL)

    def test_existing_invoices_retain_rounding(self):
        self.assertIn("x.source_metadata->>'offline_tax_rounding'='invoice_total_unrounded'", SQL)
        self.assertIn("ELSE round(round(l.quantity*l.unit_price,2)*l.tax_rate,2)", SQL)
        self.assertIn("THEN round(round(l.quantity*l.unit_price,2)*l.tax_rate,6)", SQL)

    def test_replay_fences_payload_and_expected_totals(self):
        self.assertIn("source_metadata->>'offline_operation_id'=p_operation_id::text", SQL)
        self.assertIn("pg_advisory_xact_lock", SQL)
        self.assertIn("offline_payload_signature", SQL)
        self.assertIn("p_expected_net_cents bigint", SQL)
        self.assertIn("p_expected_tax_cents bigint", SQL)
        self.assertIn("rolling back", SQL.lower())

    def test_does_not_create_a_payment(self):
        self.assertNotIn("INSERT INTO briskers.invoice_pending_payments", SQL)
        self.assertNotIn("INSERT INTO briskers.payment_allocations", SQL)
        self.assertNotIn("DELETE FROM briskers.", SQL)

if __name__ == "__main__":
    unittest.main()
