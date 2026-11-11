# P0 #453 consolidated candidate

## Delivered source and verification scope

- Owner offline single-payment finalization and bulk invoice close now save durable SQLite intents. Eligibility for the whole selection is atomic. Requests retain receipt identities, amounts, dates, methods and invoice totals. They survive restart and do not represent server confirmation. Replay requires Owner access, network permission and drained receipt/edit queues; retirement and quarantine block replay. One failed attempt holds for explicit review. The new server endpoint checks the exact snapshot and commits the result with an idempotency record in the same transaction.
- Jobs show the saved linked invoice number and saved work description. Invoice numbers open the exact document. Recorded receipts awaiting finalization have a distinct financial label.
- Existing completed-but-unpaid labor editing, mirrored Main Mechanic selector, per-person Already Paid controls and approved task colors remain. Historical prior-paid markers now travel in Owner ledger/snapshot transfer without creating payment or wage credit.
- Invoice findings use the monochrome headings “Resolved on this job” and “Unresolved findings”. Existing Add to Job behavior is retained.
- Receipt gateway, local photos, payee queues, recurring occurrence identities and prior history are preserved. No live invoice, payment, expense or payroll record was changed during this work. The new endpoint deployment added only schema and permissions; its operation log was verified empty afterward.
- The signed workflow requires six checks on the exact current source and verifies the permanent certificate, application ID, increasing version code and install-over preservation. Upgrade baselines include b2568 and the latest signed b4620.

## Owner acceptance and limits

| Area | Committed / automated evidence | Physical phone or data verification still needed |
| --- | --- | --- |
| Offline finalization | SQLite restart, repeat confirmation, partial receipt, conflict hold, same-ID retry, atomic selection and retirement tests; synthetic PostgreSQL exact-snapshot/idempotency tests | Select one and several actual fully paid invoices offline. They show saved requests until approved synchronization confirms posting/close. |
| Jobs and invoices | Saved number link and work summary widget coverage; recorded-pending status | J-48, J-49, J-52 descriptions and J-47 payment banner |
| Labor / Already Paid | Existing paid locks, completed-unpaid corrections and cross-database prior-paid transfer tests | Kam’s 0.70 hours on invoice 6369; main mechanic, split hours and task colors |
| Findings | Saved findings projection and PDF grouping | Actual invoice notes and black-and-white print |
| Offline finance | Existing payee, receipt gateway, recurring and preservation tests | Real receipt scan/edit/save/reopen; payee save/reopen; Cintas occurrence |
| Gloria | Existing recovery tests are retained, not evidence of resolution | Exact phone-local records and pending changes remain unavailable; no recovery or financial mutation authorized/performed |
| November 6 payroll | Historical expense review remains read-only and displays original IDs | Kam $600 and Chris $700 are not verified as employee-linked in available data; Reports reconciliation remains unresolved. No expense recreated. |
| J-47 task count | Financial status corrected independently of labor completion | Saved task completion must be checked on the phone; job Completed does not authorize inventing a completed labor credit. |
| Multi-item grouped findings | Not delivered | Separate planned enhancement, not represented as implemented |

This is a tested release candidate, not a claim that all phone-specific P0 records are resolved. Use the final workflow artifact and its verification evidence for the actual version, SHA, certificate and upgrade result.
