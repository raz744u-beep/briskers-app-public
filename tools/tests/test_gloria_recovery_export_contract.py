from pathlib import Path

SOURCE = Path("lib/screens/settings/local_sync_status_screen.dart").read_text()
START = SOURCE.index("Future<void> _copyGloriaRecoverySnapshot()")
END = SOURCE.index("Future<int> _pendingRecoveryOperations", START)
method = SOURCE[START:END]
assert "if (!widget.isOwner) return;" in method
assert "sync_outbox WHERE business_id=? AND id=? AND entity_type=?" in method
assert "knownCustomer" in method and "knownVehicle" in method and "knownInvoice" in method
assert "Clipboard.setData" in method
assert "local_customers" in method and "local_vehicles" in method
assert "local_documents" in method and "local_jobs" in method
assert "INSERT INTO" not in method
assert "DELETE FROM" not in method
assert "UPDATE " not in method
assert "_api." not in method
assert "if (widget.isOwner)" in SOURCE
print("Gloria recovery export owner/read-only contract: PASS")

assert "'local_invoice_detail': invoiceDetail" in method
assert "invoiceDetail['lines'] is! List" in method
