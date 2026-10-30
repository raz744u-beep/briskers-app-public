# Briskers Offline-First Master Numbering — Design v1
Date: October 29, 2026. Status: proposed only; not installed in shop APK.

## 1. Required shop behavior
Every customer, vehicle, Job, invoice, estimate, line, note, finding and payment-received record is saved immediately to on-device SQLite with stable immutable record UUIDs and operation IDs. It can be viewed and edited without Supabase, including linked records whose server UUIDs are not known yet. A failed network request must not block independent local business work.

The Owner appoints one Master number authority per shop; other enrolled devices are Slaves. Master controls the authoritative numbered invoice/estimate/job sequence, never their actual contents or funds.

## 2. Guarantee and unavoidable limits
Two devices with neither internet nor a shared local connection cannot both guarantee unique *consecutive* official numbers unless they coordinated in advance.

Method A: On shop Wi-Fi, request an official number from a local Master service, with no public internet.
Method B: Ahead of time, Master allocates nonoverlapping short numbered blocks (leases) to each device. Each device consumes its owned numbers fully offline. Numbers might not follow actual chronological creation order and unused reservations create temporary gaps.
Method C: If isolated and no numbers remain in the assigned lease, still create the invoice with a clear local provisional reference, not a blank label or fake permanent number. Assign official number when Master can be reached again.

Master has priority only for resolving a collision of display numbers. The slave invoice and its original repair lines, totals, customer, dates, notes, audit records, and payment IDs must **never** be overwritten by the Master. In a genuine conflict, only its number is corrected with an auditable alias and notification if a PDF was printed/sent.

## 3. Number authority and persistence
Store per shop and document kind: authorized master_device_id, master_epoch, next_number, eligible number-reuse ledger, claims ledger, device enrollment and active leases.
Store each lease with shop_id, kind, lease_id, device_id, first/last, epoch, consumed slots and issuer attestation. Never reclaim an unconsumed block on expiry alone, because the device may be offline and have issued numbers.
Store each claim with shop_id, immutable document UUID, operation UUID, kind, official number, lease_id, device_id, claim state and timestamp.

Local allocator uses **one SQLite transaction** to consume an eligible lease slot and atomically save the invoice, linked records, and queued sync operation. Retry with the same operation UUID must return the same number; crash before commit cannot consume a number without saving the invoice.

Server enforces uniqueness per shop/kind and across native and historical MobileBiz numbers. A number cannot collide with another shop's document or an old imported record. Before switching authority, review old APK compatibility and existing server document_counters + numbering pool.

## 4. Master reliability and takeover
Prefer a permanent on-site powered device for the shop-LAN authority instead of an Android app that the OS may suspend. Authenticate device requests and shop permissions, protect the LAN channel, persist encrypted ledger backups. For replacement, an Owner-approved new Master takes over with a new epoch; old Master must be fenced before issuing anything. Existing offline leases must remain valid until safely reconciled. Do not permit independent dual masters.

## 5. Sync, payments and UI
All records have an immutable logical UUID independent of display number; cross-device sync uses idempotent operation IDs and acknowledged versions. The queue replays customer → vehicle → Job/invoice → payment → details when network returns, but local app screens always use locally linked identities first. Auto retry triggers on app launch, foreground resume, connection recovery and bounded active interval, with serialized operations and exponential backoff. Manual Sync Now needs full queue parity including payments and mileage. Never delete a local queue entry on transport timeout alone; verify exact server acceptance first.

Payments represent locally recorded funds received; distinct from server-posted/Owner-finalized accounting. Preserve method, amount, date and immutable payment ID, never create a duplicate receipt on replay. PDF shows an official number only from a valid authority claim; otherwise it clearly shows a provisional reference. No data-changing Master overwrite.

The owner-approved eligible deleted-number reuse requirement (#186, #116) remains, but numbers inside an outstanding offline lease cannot be reclaimed until fully verified unused. Real paid/externally issued documents stay protected.

## 6. Planned rollout
A: Fix stuck Auto retries and dependent queues on existing S26 first (#388). Gloria operations customer #252 → vehicle #253 → invoice #254 → payment #255 must reconcile in place, with no duplicate or silent data rewrite.
B: Add a SQLite lease-allocator foundation and synthetic two-device test rig in separate TEST package, no hosted finance changes.
C: Authenticated offline LAN Master service, slave leases and Owner Master replacement/fencing; physical S26 and second-phone tests.
D: Reviewed backend schema and RPC validation, shop security, imported-number compatibility and controlled migration, then signed shop APK after acceptance.

## 7. Acceptance testing
Internet unavailable: two devices create complete customer/vehicle/job/invoice/payment data and search it locally.
Shop LAN available: Master and slave get unique sequential official numbers, no cloud.
Both LAN and internet unavailable: separately leased ranges issue no conflicting official numbers; no lease means a visible provisional ID.
On reconnect, operations replay in reverse arrival order with one authoritative invoice/customer/payment each. Failed network response replay is idempotent.
Corrupt duplicate-number test: Master retains claim, Slave receives corrected vacant number with both contents/payment chains intact and visible alias.
Power loss: no half-invoice/no consumed slot without durable record; Master replacement doesn't allow duplicate issuing.
Deleted eligible numbers reused safely, but never while an offline device may still hold them.
Legacy MobileBiz imports, manual owner number floors, Invoice/Estimate/Job kinds and multi-tenant permissions remain valid.

**This document is an implementation plan, not a claim of a working master/slave build.**