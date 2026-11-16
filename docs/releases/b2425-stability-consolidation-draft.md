# Briskers b2425 stability consolidation — draft release gate

**Track:** regular Briskers shop APK on S26 Ultra. This is NOT the separate Note 9 experimental app.

**Source baseline:** `fix/b2423-first-open-local-cache-313` at `4a627b2dc3cc2cb53c92a8b2ce3d5d189b052f23`.
**Integration branch:** `fix/b2425-detail-firstpaint-regression-20261024` (PR #316).
**Production merges / hosted SQL / live records touched:** none.

## Source included in draft

- Jobs: paint permission-scoped cached Job before linked-doc list; hydrate linked documents and expenses independently; maintain local status and quick edits before remote flush; Auto Jobs remote pull no longer gates retained list.
- Customers: cache-first directory retained from base; opening detail shows selected authorized list-row preview while actual local customer/vehicles hydrate; no premature financial/edit actions. Customer Notes and Findings paint local content before remote and attachment downloads. Notes preserve pending local edits and staged images during server refresh; Note thumbnails and full-screen photo viewer read cached files without signed URLs.
- Estimates / Invoices: selected document identity (read-only) visible immediately while the exact local detail and pending financial/payment projections complete. Independent local memo/payment/edit reads are now parallelized, while accounting projections stay ordered. Coalesce overlapping large document index/detail pulls by business to reduce contention. Do not show unverified financial totals or enable sensitive actions from row preview alone.
- Expenses: all main/Job/Invoice clicked transaction rows now supply read-only first-frame preview in Auto and Force Offline; authoritative detail/permissions required for changes.
- Findings: invoice uses the existing full photo-capable customer vehicle component, scoped to one vehicle; separate cache key prevents replacing customer-wide Findings; identity-filtered cached entries prevent mixed-vehicle photos; confirmed repair chooser allows completed historical jobs and does not modify financial records; redundant rebuilds no longer restart Findings requests.
- UI: large **rectangular rounded-corner** module-color `+ New` button just above navigation on Customers, Jobs, Appointments, Estimates, Invoices, Expenses. Retain existing permission guards and action semantics, safe keyboard inset and scroll clearance.
- Additional Oct23 approved changes ported from PR #310: Standard Note keyboard safe-area, New Estimate first frame without customer prefetch, Expense modal colors and quick-template title case.
- Incremental Android idle media: bounded prefetch from locally synchronized Findings/pre-inspection photo references **and previously cached customer-note/expense receipt attachment metadata** via existing WorkManager when **charging and on unmetered Wi-Fi**. An additional bounded metadata pass retrieves *missing* receipt details only, without touching pending financial records. In-use Expenses and Customer Notes prefetches are throttled. Settings shows locally available files versus **known** attachment references, clearly not a verified whole-shop total. Does NOT yet obtain uncached historical notes, all receipt metadata or ExpenseIQ originals from other devices. No deletion of local originals or pending uploads.

## Mandatory CI + device release gates

- [ ] Exact-head Flutter analyzer clean.
- [ ] All regression/widget tests green, including new b2425 local-first, buttons, scoped Findings, offline mirror, Job quick edits and financial safety.
- [ ] Exact-head iOS compile parity green.
- [ ] Signed release APK built from the **exact test-passing SHA** with the permanent certificate; record version/build/SHA-256 and clean install-over result.
- [ ] S26: rapid switch across all main tabs and reopen existing records; measure tap-to-first-content and first fully usable detail; no ten-second waits for already cached data.
- [ ] S26: Auto, Force Offline, airplane mode, slow DNS, app relaunch and background/foreground transitions. Existing local records and photos remain readable.
- [ ] S26: Expenses date-range verified totals unchanged; existing invoice/payments/amounts/tax/mileage unchanged; queued edits never silently dropped/duplicated.
- [ ] S26: Invoice #6354 known photo finding and Customer/Job Findings same source and full image; no mixed-vehicle records; resolve history selects the actual Job.
- [ ] S26: Customers/Jobs/Appointments/Estimates/Invoices/Expenses bottom `+ New` shape, position, color, action and role guards accepted.
- [ ] Preserve finding_action outbox #182/#183 pending/verification state; no blind resend/reset.
- [ ] Note 9 separate package remains untouched; no production database modifications.
- [ ] Explicit Owner phone acceptance before any main merge or production release.

## Not yet completed by this source candidate

- Complete **all-record/all-photo** offline bootstrap and delta mirror. The current metadata inventory is limited to locally indexed Findings/pre-inspections plus previously cached note/receipt references; historical ExpenseIQ originals and uncached remote notes/receipts remain outside coverage. Per-device *known* photo counts are implemented, but server-authoritative completeness, total bytes, download status per object, storage policy, revocation and cross-device verification are still required.
- Instrumented measurement and guaranteed elimination of every record-detail delay on the physical S26.
- Full historical PR #298/#310 integration audit and iOS/device acceptance.
- Signed APK assembly and distribution (not implied by CI or a draft PR).
- Owner Delete Job hosted backend and unrelated deferred features remain separate.

Do not label any checkbox complete without exact-commit evidence. Never replace one fixed UI screen with a stale branch snapshot.
