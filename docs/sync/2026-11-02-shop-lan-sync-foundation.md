# Briskers Shop LAN Sync — isolated implementation plan (2026-11-02)

Related: #389 (offline master/slave, LAN and kiosk) and #388/#396 (Gloria/cloud replay). This document **does not claim LAN data replication is implemented**.

## Goal and hardware

- Owner's Samsung S26 Ultra: **Master of official document-number allocation only** (not master of all edits).
- Secretary's Android phone: independently writable local database, peer sync.
- Android tablet kiosk: stores check-ins locally, sends them to authorized phones; **never** receives payroll or the full accounting/customer database.
- Primary transport: shop Wi-Fi LAN, even if ISP/internet is disconnected. Phones must be on a network without client/AP isolation; no port forwarding or cloud dependency. Later optional Nearby Connections / Wi-Fi Direct fallback.
- Preserve local-first behavior in both app Auto and Offline modes. LAN sync is an independent toggle; disabling cloud must **not** disable LAN.

## Non-negotiable data safety

1. Every device commits its own business transaction to local SQLite before it attempts any network send. All existing records, payments, numbers and queued Gloria operations are left untouched by this experimental branch.
2. Model each change as a globally unique immutable operation UUID with shop/business ID, origin device UUID, local entity UUID, entity/version, required permission scope, payload digest and dependencies. Use one logical durable journal and **separate peer/cloud delivery receipts**, not one shared `synced` boolean. A LAN ACK never means cloud ACK.
3. Sender retains changes until receiver has **atomically committed** the idempotent operation and its durable receipt; a lost ACK is handled by safe replay. Same operation ID + different digest is an **integrity conflict**, not a silent overwrite.
4. Apply dependencies and authorization before data writes. A kiosk can create check-ins only; cashier/secretary may receive authorized customer and job records but never payroll/private Owner data. Finalization and sensitive actions remain Owner-controlled. Protect tombstones from resurrection.
5. Do not copy/overwrite a whole SQLite file, alter existing imported invoice numbers, merge independent payments by amount, or use last-writer-wins for financial records. Recover from interruptions/restart without deleting the sender's queue.
6. Pair devices with Owner approval (one-time QR/short code) and pinned device credentials. Encrypt and authenticate **all actual business data traffic** end-to-end. No customer/business payload travels over the unencrypted preliminary probe.
7. Maintain an explicit Master epoch/term and local durable number/lease claims. Never create two active Masters. Provisional invoice numbers and pre-leased 50–100 buffers require the #389 reconciliation rules; no externally shared final number may be silently changed.
8. Show **Saved locally**, **Delivered to Owner/Secretary**, **Cloud synced** separately, with last successful timestamps, queue counts and meaningful errors. Android may suspend the Owner phone's listener; do not advertise an instantaneous guarantee while the phone sleeps.

## Delivery slices

### Slice A — probe and safe planning (this branch)
- A **non-sensitive read-only HTTP LAN probe**, with an explicit bind address and a test client. It returns only protocol name/version, **not** device/shop/customer information. Never run it automatically on shop devices or bind to the LAN in production yet.
- Pure Dart batch planner that enforces shop isolation and the initial kiosk-check-in recipient matrix, with duplicate-operation collision checks. No payload transmissions, database migrations, edits or ACK side effects.
- Loopback and unit tests. This is a testable transport foundation, **not** an APK for business data sync.

### Slice B — owner approved device pairing, transport
- Android local network discovery (mDNS/NSD) with manual IP/QR fallback. Test the router with **internet unplugged**.
- Authenticated encrypted session, pinned keys, version/capability negotiation, rotation and revocation. Verify multi-device enrollment and no secret leakage.
- Durable peer membership, journal and per-peer receipt tables, migrations and crash/retry tests. Do not reuse cloud-outbox `state` as LAN delivery state.

### Slice C — first live vertical path
- Kiosk check-in locally saved -> encrypted LAN relay -> persisted on Owner and Secretary -> local UI notification. Match existing customer safely, never auto-create a duplicate by fuzzy matching.
- Test device asleep/restart, off-network delivery, same operation replay, lost ACK, out-of-order dependency, revoked kiosk, deleted record, duplicate name, network with ISP disabled.
- Keep release behind a feature flag; do not roll into S26 business APK before independent tests.

### Slice D — regular shop entities and numbering
- Customer/vehicle/appointment/job/document/tasks scoped deltas and explicit conflict review.
- Master-local invoice number API with durable claims, Master fencing and 50–100 provisional buffer; protect historical/imported numbers. Reconcile only the number, never other invoice fields.
- Received payment, Owner delete and payroll **last**, each with immutable audit/idempotent local transaction and permission tests. Cloud replay stays independent.

## First acceptance

1. Two devices on the same shop Wi-Fi discover/connect when the ISP cable is unplugged.
2. Unauthorized or unpaired peers cannot retrieve any business data.
3. The kiosk check-in survives an app restart and delivers exactly once in the receiver's durable database, including after a lost ACK/replay.
4. A sleeping/disconnected phone shows pending delivery, then catches up after reconnect; locally saved records never disappear.
5. A different shop, an unauthorized role, or a revoked device cannot receive data.
6. Existing b2552/Gloria invoice and payroll branches remain unchanged until their respective acceptance gates.

## Implementation boundary

Do not interpret a successful read-only probe as secure pairing or working record sync. An Android signed APK and on-device test with two physical devices are still required to validate LAN networking and Android background behavior.


## Cross-platform addition — iOS and Android peers (Nov 2, 2026)

The Briskers shop LAN sync protocol **must be cross-platform**: iPhone/iPad peers exchange the same versioned, encrypted, business-scoped change operations and durable ACKs as Android phones and the Android kiosk, using local Wi-Fi with no internet or Supabase dependency. A paired iPhone may be an Owner/Secretary/authorized staff peer; the Owner's Samsung remains number-authority until a separately authorized Master transfer occurs.

- Prefer interoperable IP transport (authenticated TLS over TCP/HTTPS/WebSocket) and cross-platform mDNS/DNS-SD/Bonjour discovery with manually entered IP/QR fallback. Do **not** base the canonical protocol on Android-only Nearby Connections, Wi-Fi Direct, or Apple-only Multipeer Connectivity. Platform-specific nearby connection methods are optional additional transports only.
- On iOS declare `NSLocalNetworkUsageDescription` and registered `NSBonjourServices` in Info.plist; request Local Network permission appropriately and explain when it is denied. Use Apple's Network framework/Bonjour APIs for discovery where necessary. Android needs equivalent multicast/NSD permissions and device checks.
- Local SQLite schema, immutable UUIDs, signed/encrypted operation envelope, role capabilities, server-independent peer receipts, invoice lease protocol, and conflict rules **must be platform-neutral**, so a change made on iPhone is indistinguishable in meaning from the same change made on Android.
- **Background limits:** iOS suspends ordinary background apps; Android can similarly suspend receivers. Never promise uninterrupted peer-to-peer delivery to a sleeping phone. Keep local changes pending and retry on foreground/reconnect. To support reliable kiosk-to-staff fan-out, consider the powered Android kiosk as an explicitly enrolled queue relay (restricted records only), or a dedicated shop hub. The kiosk still must never be granted payroll or unrestricted financial access.
- Test Android-to-iPhone, iPhone-to-Android, and mixed three-peer fan-out with the ISP disconnected; cover iOS permission denied, app suspended/terminated, lock screen, restart, re-pairing, duplicate operation, offline operation recovery, and Master-only number allocation.
- An iPhone away from shop Wi-Fi requires separately authorized remote/cloud sync over internet; direct shop-LAN sync cannot reach it remotely.
- Status: **cross-platform requirement**, not yet implemented; first draft PR only contains read-only Dart probe and pure batch planner, with no iOS device acceptance.


## Complete device matrix — shop and commercial edition (Nov 2, 2026)

Owner-confirmed target mix: Android phones, iPhones, iPads, Android tablet kiosk, optional Windows desktop/laptop in a **browser**, and optional Mac/MacBook in a **browser**. Android tablets outside kiosk mode also supported. This is an architecture target, not a claim that these clients already synchronize.

| Device | Preferred client | Storage and offline behavior |
| --- | --- | --- |
| Android phone/tablet | Native Flutter app | Durable local SQLite, same shop LAN peer protocol |
| iPhone/iPad | Native Flutter app | Durable local SQLite, same shop LAN peer protocol; handle iOS local network privacy and app suspension |
| Android check-in kiosk | Restricted, always-on native app | Local check-in queue; narrowly authorized relay capability, *never* unrestricted payroll/accounting data |
| Windows desktop/laptop | HTTPS web app in browser | Browser local database/cache where appropriate; connect through shop LAN gateway; offline local editing only after explicit PWA/database durability tests |
| Mac/MacBook | Same HTTPS web app in Safari/Chrome/Edge | Same browser-capability and persistence tests as Windows |

### Browser-specific interoperability

- **Do not** assume a webpage can run Android/iOS native peer discovery, open incoming listening sockets, or act as an always-available LAN peer. Have browser clients connect **outbound** over authenticated HTTPS/WSS to a shop gateway/hub that speaks the **same versioned change protocol** as the native apps.
- Shop gateway/hub is a logical capability, not a mandatory new physical purchase at this stage. Investigate hosting it in a reliable always-powered shop device; the Android kiosk is a *candidate*, contingent on Android service lifecycle, power/battery health, local HTTPS certificates and strict role/tenant isolation. A dedicated low-power LAN hub may later be justified for reliable browser availability and fanout.
- For browsers to load Briskers when ISP is down: either serve a signed/secure web app over the LAN from an always-on host, or use a properly installed/cache-primed PWA with tested service worker and local data storage. A never-before-loaded public website cannot be guaranteed to open offline. Browser background sync is not universally supported, so never promise delivery when the tab is closed.
- Browser secure-context rules, CORS, network permissions, TLS certificates and origin limitations must be tested in Windows Chrome/Edge and macOS Safari/Chrome. Chrome Local Network Access may prompt on public-to-LAN access; avoid relying on browser-specific APIs. See https://developer.chrome.com/docs/modern-web-guidance/guides/security/local-network-access and https://developer.mozilla.org/en-US/docs/Web/API/Background_Synchronization_API.
- Do not silently equate a browser cache with native device SQLite; implement an explicit storage/replay layer, encryption/permission model, crash safety, and offline acceptance per supported browser. Storage eviction, private browsing, multiple tabs, and logout need explicit handling.
- All devices share **business IDs, immutable entity/operation IDs, durable dedupe and ACK semantics, authorization, invoice-number authority, conflict/tombstone rules**, independent of runtime and storage.
- Remote browser access outside the shop must use authenticated internet/cloud routing or a secure approved remote access path; no LAN-only discovery outside the shop. Supabase remains background synchronization, not a required local-shop transaction processor.

### Interoperability acceptance matrix

1. Android -> iPhone and iPad -> Android on same shop Wi-Fi with ISP unplugged.
2. Native phone -> Windows Chrome/Edge browser via LAN gateway, then browser edit -> Android/iPhone, with all authorization and idempotency checks.
3. Native phone -> Mac Safari browser via gateway, including offline/cached-app tests where supported.
4. Kiosk check-in fanout -> both phone platforms and authorized desktop browsers without giving kiosk the whole customer directory or financial records.
5. App closed / device asleep / browser tab closed: sender keeps local change, receiver catches up on next eligible session without duplicate records.
6. Mixed-platform concurrent edits and numbering leases, with Owner-only final number authority and no silent overwrite of payments.
7. HTTPS, permission denied, invalid/revoked peer, failed certificate, guest Wi-Fi isolation and LAN gateway unavailable scenarios produce honest status without losing local work.

Design sequence: **native Android <-> native iOS** peer transport and authenticated journal first; **browser via secure LAN gateway** second; reliable cross-device operational workflows and safe number leasing next. Do not require Windows or Mac native applications initially.
