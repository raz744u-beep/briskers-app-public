from decimal import Decimal, ROUND_FLOOR, ROUND_HALF_UP
from pathlib import Path
import unittest

SQL = Path("tools/recovery/offline_invoice_exact_total_v2_DRAFT.sql").read_text()
API = Path("lib/services/briskers_api.dart").read_text()
DRAFT = Path("lib/services/offline_document_draft_service.dart").read_text()
STATUS = Path("lib/screens/settings/local_sync_status_screen.dart").read_text()
D = Decimal
CENT = D("0.01")
RATE = D("0.0975")
LINES = [
    ("2", "1681.98"), ("3.6", "150"), ("1", "495"),
    ("1", "51.67"), ("1", "225.32"), ("2", "4.89"),
    ("1", "123.32"), ("7", "1.58"), ("10", "150"),
    ("2", "38"), ("1", "385.66"), ("1", "160.32"),
    ("1", "18.45"), ("1", "26"), ("1", "150"),
    ("2", "4.98"), ("1", "7.38"), ("1", "28"),
]


def cents(value):
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


def allocation(lines, rate=RATE):
    """Independent Decimal model for the DB's largest-remainder cent assignment."""
    raw = [cents(D(qty) * D(price)) * rate for qty, price in lines]
    floors = [int((value * 100).to_integral_value(rounding=ROUND_FLOOR))
              for value in raw]
    total_cents = int(cents(sum(raw)) * 100)
    extras = total_cents - sum(floors)
    # Stable ordering: descending remainder, then source position.
    order = sorted(range(len(raw)),
                   key=lambda i: (-(raw[i] * 100 - floors[i]), i))
    allocated = floors[:]
    for i in order[:extras]:
        allocated[i] += 1
    return [D(value) / 100 for value in allocated]


class ExactOfflineInvoiceRecoveryContract(unittest.TestCase):
    def test_new_api_is_versioned_and_permission_checked(self):
        self.assertIn("briskers_sync_offline_quick_invoice_v2(", SQL)
        self.assertIn("briskers.require_permission(p_business_id,'invoices.create')", SQL)
        self.assertIn("briskers.require_permission(p_business_id,'jobs.create')", SQL)
        self.assertIn("REVOKE ALL ON FUNCTION public.briskers_sync_offline_quick_invoice_v2(", SQL)
        self.assertIn("TO authenticated", SQL)

    def test_two_decimal_columns_require_explicit_cent_allocation(self):
        self.assertIn("x.source_metadata->>'offline_tax_rounding'='invoice_total_unrounded'", SQL)
        self.assertIn("tax_amount=round(round(l.quantity*l.unit_price,2)*l.tax_rate,2)", SQL)
        self.assertIn("floor(l.net_amount*l.tax_rate*100)::bigint as base_cents", SQL)
        self.assertIn("row_number() over", SQL)
        self.assertIn("target_cents-base_total_cents", SQL)
        self.assertIn("tax_amount=a.tax_cents_exact", SQL)
        self.assertNotIn("round(round(l.quantity*l.unit_price,2)*l.tax_rate,6)", SQL)

    def test_replay_fences_payload_person_vehicle_and_amounts(self):
        self.assertIn("source_metadata->>'offline_operation_id'=p_operation_id::text", SQL)
        self.assertIn("pg_advisory_xact_lock", SQL)
        self.assertIn("AND customer_id=p_customer_id", SQL)
        self.assertIn("AND vehicle_id IS NOT DISTINCT FROM p_vehicle_id", SQL)
        self.assertIn("offline_payload_signature", SQL)
        self.assertIn("coalesce(p_document_date::text,'<null>')", SQL)
        self.assertIn("p_expected_net_cents bigint", SQL)
        self.assertIn("p_expected_tax_cents bigint", SQL)
        self.assertIn("rolling back", SQL.lower())

    def test_client_routes_mismatch_only_through_explicit_owner_v2(self):
        self.assertIn("syncOfflineQuickInvoiceExactTotal(", API)
        self.assertIn("'briskers_sync_offline_quick_invoice_v2'", API)
        self.assertIn("required int expectedNetCents", API)
        self.assertIn("required int expectedTaxCents", API)
        self.assertIn("required int expectedNetCents", API)
        self.assertIn("bool exactTotalRecovery = false", DRAFT)
        self.assertIn("final requiresExactTotal =", DRAFT)
        self.assertIn("if (requiresExactTotal && !exactTotalRecovery)", DRAFT)
        self.assertIn("requiresExactTotal\n                ? _api.syncOfflineQuickInvoiceExactTotal(", DRAFT)
        self.assertIn(": _api.syncOfflineQuickInvoice(", DRAFT)
        self.assertIn("if (!widget.isOwner)", STATUS)
        self.assertIn("exactTotalRecovery: true", STATUS)
        self.assertIn("() => _documentDrafts.flush(widget.businessId)", STATUS)

    def test_never_posts_a_payment_or_deletes_original_data(self):
        self.assertNotIn("INSERT INTO briskers.invoice_pending_payments", SQL)
        self.assertNotIn("INSERT INTO briskers.payment_allocations", SQL)
        self.assertNotIn("DELETE FROM briskers.", SQL)

    def test_gloria_one_cent_mismatch_corrected_by_allocation(self):
        bases = [cents(D(qty) * D(price)) for qty, price in LINES]
        naive_tax = sum(cents(base * RATE) for base in bases)
        taxes = allocation(LINES)
        self.assertEqual(sum(bases), D("7181.88"))
        self.assertEqual(naive_tax, D("700.24"))
        self.assertEqual(sum(taxes), D("700.23"))
        self.assertEqual(sum(bases) + sum(taxes), D("7882.11"))
        self.assertTrue(all(value == cents(value) for value in taxes))

    def test_edit_reallocates_tax_without_rounding_drift(self):
        updated_lines = LINES.copy()
        updated_lines[0] = ("2", "1700.01")
        edited_tax = allocation(updated_lines)
        edited_bases = [cents(D(qty) * D(price))
                        for qty, price in updated_lines]
        expected_whole_tax = cents(sum(base * RATE for base in edited_bases))
        self.assertEqual(sum(edited_tax), expected_whole_tax)
        self.assertTrue(all(value == cents(value) for value in edited_tax))
        self.assertNotEqual(sum(edited_tax), sum(allocation(LINES)))

    def test_allocation_zero_tax_and_stable_replay(self):
        self.assertEqual(allocation(LINES, D("0")), [D("0")]*len(LINES))
        self.assertEqual(allocation(LINES), allocation(LINES))
        self.assertEqual(sum(allocation([("1", "0.01"), ("1", "0.01")],
                                        D("0.25"))), D("0.01"))


if __name__ == "__main__":
    unittest.main()
