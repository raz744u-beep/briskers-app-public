# Invoice 6359: duplicate listing repair

Read-only trace, 2026-11-17, business 93403e82-42b4-465c-b539-b5e127104f1b.

| Source | Internal invoice ID | Creation identity | State |
| --- | --- | --- | --- |
| Original phone record | local-invoice-f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385 | local ID suffix | Owner-confirmed Closed, Gloria, J-40, 2016 Audi A8L |
| Downloaded cloud index | 4bc125a0-7954-4036-82f2-4650847463f3 | source_metadata.offline_operation_id = f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385 | Stale issued/Open state |

The original Job is local-job-f9eaf3b3-3a9c-427a-8c8f-8f01d0fa6385. The cloud Job is c6a23164-c09a-490d-8b00-c3e84e7282fb (J-40). Cloud has only one invoice matching 6359, total 7882.11, 18 lines, no payment allocations, and its old October state. The phone screenshot shows two listings after invoice-history download. Existing diagnostic code independently identifies the original local invoice and Job IDs.

The matching creation-operation UUID proves the identity. Public number matching alone is never sufficient. A narrowly scoped alias manifest additionally verifies the original numbered J-40 row and amount before registering the alias. It changes visibility and navigation only. Both physical index entries and all detail/ledger records remain intact. The original canonical index survives replacement imports. No live cloud record was changed.

Expected phone receipts remain 3000.00 + 4882.11 = 7882.11. Tests use isolated copies to compare exact stored detail/payment JSON before and after alias registration, restart and import replay. The actual S26 database is unavailable here; installation and Owner phone verification are still required.

Separate-record deletion now creates a permanent exact-ID local tombstone plus Owner audit snapshot. Confirmation names the selected invoice. It preserves the Job and financial evidence. Local import, detail-cache writes and navigation honor the tombstone. No whole-Job deletion or cloud payment finalization is invoked.

Opening delay: removed shop-wide payroll initialization from invoice loading; restricted pending catalog-tax repair to the selected document and skipped catalog hydration if it has no pending edits. Replaced retirement-ID scans with indexed exact-ID checks in detail navigation. No S26 timing measurement is claimed.
