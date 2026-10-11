# INT-APP-002 — Offline create then cancel replay (2026-10-10)

Environment: Briskers Dev Supabase `coensavcnuwuqaeszohb`.

Test transaction used disposable customer, confirmed appointment, and one UUID for create and cancel operation identities. Authenticated owner session was set within the transaction.

Checks:
- First idempotent create returns new appointment identity.
- Revision-checked cancel marks it cancelled.
- Retried create returns same appointment identity.
- Retried cancel returns same row version.
- Exactly one appointment exists and retains cancelled status in transaction.
- Explicit ROLLBACK, followed by checks verifying **zero** synthetic customers, appointments, create operation keys, and cancel operation keys persisted.

Result: **PASS**. Does not replace real-device interruption tests.

Pending: check-in conflicts, offline owner deletion/tombstones, on-device verification.
