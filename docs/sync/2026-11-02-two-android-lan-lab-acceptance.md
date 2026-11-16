# Two Android phones — shop Wi-Fi sync lab (2026-11-02)

**Status: implementation committed on draft PR #410; CI and physical acceptance are separate gates.** This is an isolated **synthetic-only Android APK** with application ID `com.briskers.lanlab.briskers_app`, not a module enabled in the installed shop build 2552.

## What this particular build actually does

- Starts a local IPv4 listener on port **48571** only while the test app is running.
- Shows a QR code containing one phone's private Wi-Fi IP, port, protocol version, and high-entropy test pairing secret. Do not share it publicly.
- On the second phone, scan the QR. It adopts the shared test key and can initiate bidirectional synchronization.
- Each phone can create a short **synthetic note**, with a random immutable operation ID and SHA-256 content digest. Notes are stored in **separate isolated app support storage**, using flush + atomic rename, and survive ordinary app restarts.
- Synchronization sends/replies with AES-256-GCM authenticated encryption. A receiving phone writes and validates every incoming note before its encrypted response acknowledges the operation IDs. Replaying a note doesn't duplicate it; conflicting content IDs are rejected.
- Incoming notes refresh the receiving test UI. Both phones can independently add local notes, and the second phone can pull/push when it reconnects.
- **No Supabase, cloud, customer, invoice, payment, payroll, or normal Briskers DB connection is initialized.** Production app identity is unchanged.
- Uses a fixed port and manually QR-scanned IP, **not** automatic mDNS discovery yet; both phones need to be on the same unisolated Wi-Fi network.

## Two-phone acceptance procedure

1. Install the **separate** APK built by GitHub Actions: workflow **Briskers LAN two-Android TEST APK** on PR #410. This is a debug-test artifact, not a production signed release.
2. On **Samsung S26 Ultra** and **Samsung Note 9**, connect to the **same shop Wi-Fi** (do not use guest Wi-Fi or AP/client-isolated SSID). The TEST targets SDK 36, so Android 17 allows its local networking through the INTERNET permission without a new Local Network prompt; SDK 37 production migration will require explicit runtime permission.
3. Open the LAN TEST app on both phones. Verify the top status shows a private IP address on each and that the local listener started. Keep both apps foreground during first connection.
4. On S26, leave its QR code visible. On Note 9, tap **Scan other phone pairing QR**, scan the S26 code, and verify the paired peer IP.
5. On S26, create **"Hello from S26"** using **Save test note**. On Note 9, create **"Hello from Note 9"**.
6. On Note 9, tap **Sync both directions over shop Wi-Fi**. Check both records appear on both devices; S26 should refresh incoming notes automatically. Tap **Refresh locally saved notes** if needed.
7. Press Sync again. Neither note should be duplicated.
8. Disconnect the shop **internet/ISP uplink** while leaving the Wi-Fi router powered and both phones connected. Add a new test note on each and sync again; it must work.
9. Temporarily disconnect Note 9 from Wi-Fi; create a note locally, reconnect and sync. Verify it is delivered without losing the previous notes.
10. Close and reopen both test apps. Verify all synthetic notes persist locally and QR pairing still works; if a device changes IP, rescan its QR.

## No-go / must fix

- Cannot install beside Briskers, cannot read/scan QR, cannot acquire Android 17 LAN permission, or cannot connect.
- Any duplicate after repeated sync; any note lost after restart/reconnect; a wrong pairing key successfully transfers data; app attempts Supabase or accesses actual business records.
- No acknowledgment should be displayed unless the receiver has saved the incoming operations.

## Implementation limits that remain

- No enrolled shop identities or role-based real-data permissions yet. The shared pairing QR is a temporary high-entropy **lab secret**, stored only for synthetic tests, not a production credential management system.
- No durable per-peer/cloud ACK tables or conflict reconciliation for business records, no Master invoice-number allocator integration, no live customer/job/receipt sync.
- QR/manual IP rather than automatic discovery; local IP may change if the router reassigns DHCP. Consider mDNS/NSD next.
- Android background restrictions may suspend the listener. Delivery is on-demand (keep receiver app open); queued local notes retry later, no fake instant-delivery guarantee.
- Real business record sync requires durable SQLite journal, enrollment/authentication, roles, financial idempotency, encrypted transport, tombstones, and acceptance gates from issue #389.

## Build and verification

Workflow file: `.github/workflows/shop-lan-android-lab.yml`. It creates a **distinct Android package** from source in CI, declares INTERNET permission and deliberately targets SDK 36 for compatibility with the available Android CI toolchain (SDK 37 will require a new Local Network runtime-permission implementation), tests the encrypted two-device transport and existing protocol, analyzes code, builds a debug APK with target `lib/shop_lan_lab_main.dart`, and uploads an artifact.

Do **not** report this lab as a complete multi-device business synchronization system. Physical S26 + Note 9 confirmation is required before extending to customer/check-in/job data.
