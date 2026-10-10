# APP-001 — Briskers Dev appointment permissions integration results

Date: 2026-10-10
Environment: Briskers Dev, PostgreSQL RPC functions.
Method: authenticated owner/office identities in a SQL transaction using a **synthetic customer and appointment**. Entire transaction rolled back.

## Passed

- Office role successfully updates a confirmed appointment through `briskers_update_appointment`.
- Office role is denied `briskers_delete_appointment`.
- Office role is denied editing a cancelled appointment (separate rolled-back synthetic fixture).
- Owner role updates a cancelled appointment through `briskers_update_appointment`.
- Owner role deletes a history-free appointment through `briskers_delete_appointment`.
- After rollback: 0 synthetic customers, 0 synthetic appointments.
- GitHub CI passed for appointment UI branch prior to this report.

## Fixture note

An initial attempt used a nonexistent `checked_in` status in the appointments table; the table rejected it. A checked-in appointment is instead represented by a Job link and must be tested with a realistic linked-Job fixture, which was **not** done in this run.

## Outstanding

- Authenticated checked-in appointment + linked Job tests, including immutable customer/vehicle association
- Offline edit/delete durable outbox, conflict handling and cross-device deletion tombstones
- Mobile Android/iOS verification

Do not treat APP-001 as fully implemented or verified yet.
