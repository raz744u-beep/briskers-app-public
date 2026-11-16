# Briskers Shop LAN — Automatic Sync TEST #16 (2026-11-03)

## Purpose
After Owner's successful two-Android synthetic note sync in TEST #15, the next isolated test removes the need to press Sync manually. It does **not** integrate live Briskers records.

### Current implementation
- Paired Android TEST app automatically pushes/pulls its synthetic notes on startup, after pairing, after saving a note, and repeatedly while the app is in foreground (nominal six-second interval).
- Failure keeps local records and retries with bounded exponential backoff up to 48 seconds. Automatic sync cannot create overlapping network transfers; multiple triggers are coalesced into one follow-up transfer.
- Returning to foreground immediately triggers catch-up; moving to background pauses *outgoing* scheduled polling. An incoming connection requires Android to keep that app's listener alive and cannot be guaranteed when the phone is asleep.
- UI shows the automatic connection/transfer state, success counts, or a clear retry message. Optional **Sync Now** remains for manual testing.
- The receiver still validates incoming authenticated AES-GCM envelopes and writes notes durably before acknowledging them; duplicate retries remain idempotent.
- No Supabase/cloud calls or real financial/customer/employee record access.

### Pairing on two Android phones
- On the S26, show the pairing QR. On Note 9, scan it **once**. The Note 9 stores the S26 endpoint and syncs automatically while its app is running.
- The S26 can receive and refresh newly pushed notes even though it has not scanned the Note 9's QR. New S26 notes will appear on Note 9 at the next automatic poll while Note 9 is foreground.
- This is deliberately **one remembered peer** (one QR origin). General multi-device fan-out, per-device subscriptions and discovery are separate future phases.
- Wi-Fi router can have Internet connected or disconnected. Both phones must be on same network without client/AP isolation.

### Test #16 installation identity
TEST #15 debug signing certificates were different from TEST #13 GitHub debug certs. Since replacing #15 with a differently signed build may require uninstalling and losing synthetic test data, TEST #16 uses a **different Android package identity** `com.briskers.lanauto16.briskers_app`. It can sit alongside #15 and the regular shop Briskers app. This first installation requires pairing TEST #16 once; the new app has its own synthetic notes, which is intentional. Never imply that #15 notes were migrated. Stable signing for future test updates requires a persistent protected signing key; do not commit the private key to this public repository.

### Two-device acceptance
1. Install the same TEST #16 APK on S26 and Note 9, keeping TEST #15 installed.
2. Pair Note 9 using S26 QR. Leave both TEST #16 apps open on the same Wi-Fi.
3. Without pressing Sync Now, save a note on **Note 9** and verify it appears on S26 automatically.
4. Without pressing Sync Now, save a note on **S26** and verify it appears on Note 9 after the next poll.
5. Repeat with additional notes and confirm no duplicates on either phone.
6. Turn off Note 9 Wi-Fi only, save a note locally, reconnect, bring app to foreground, and verify it catches up without tapping Sync Now.
7. Close and reopen both apps. Verify local notes remain, pairing is remembered and auto-sync resumes.
8. If possible later, unplug the router's ISP uplink but keep Wi-Fi active; repeat.
9. Test Android backgrounding/lock: app may be suspended. Pending work must catch up after foreground; no false instant/background delivery guarantee.

### Gate before real shop integration
Successful physical #16 acceptance is necessary but not sufficient. Production requires per-employee enrolled device credentials and revocation, role/field-scoped local snapshots and changes, durable per-device ACKs and common outbox, membership/permissions, tombstones, and financial safety. Mechanic devices must **never** receive the unrestricted owner/secretary dataset. See issue #389 and PR #410.
