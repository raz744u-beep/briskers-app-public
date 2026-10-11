# INT-CVA-001 — Customer → vehicle → appointment chain (2026-10-10)

Briskers Dev Supabase; isolated authenticated owner session, transaction rollback.

- Created mock customer using `briskers_offline_create_customer_idempotent`; exact retry returned identical customer ID.
- Created vehicle linked to that customer using `briskers_offline_create_vehicle_idempotent`; exact retry returned identical vehicle ID.
- Created appointment linked to both using `briskers_sync_offline_appointment_create`; exact retry returned identical appointment ID.
- Verified row in `briskers.vehicle_customers` links correct business, vehicle, customer.
- Verified `briskers.appointments` references correct business, customer, vehicle.
- ROLLBACK; verified zero diagnostic customer/appointment and replay operation keys remain.

**PASS — server RPC integration only.** This is not an end-to-end phone offline→reconnect test. CI for SQLite customer creation/rekey tests still needs verification. Check interrupted response, app restart and multi-device behavior before release.
