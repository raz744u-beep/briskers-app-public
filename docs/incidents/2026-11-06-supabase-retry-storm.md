# Supabase retry storm — November 6, 2026

## Finding and evidence

Support traced the first looping appointment deletion to October 21 at approximately 17:45 UTC. Its Dart/3.13 user-agent identifies the initiating HTTP client family, not the device, APK, or number of original HTTP requests.

Live read-only inspection on November 6 found PostgREST **14.5**. All three incident functions deliberately raised **40001** for business-version conflicts. Supabase's November 4 knowledge-base article describes indefinite **server-internal** transaction retries on PostgREST 14 for this exact code. Thus a single stale RPC can loop before the Flutter exception handler ever receives a response. Client retry protections alone cannot repair this incident mechanism.

Reference: https://supabase.com/kb/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b

The historical October 21 appointment deletion implementation (`19e82aab`) already stopped a returned 40001 conflict. October 30 commit `91864b93` additionally recognized the missing-appointment message; mileage fencing was added in `5eafbcd4`. The foreground minute timer was added October 29 (`03fb4e3e`), after the incident's reported start. These facts do not support blaming that timer or claiming that the current deletion handler lacked conflict handling.

The exact original APK/device remains unidentified. An older APK can initiate a stale request, but is not necessary to explain the continuing server loop. Support should correlate the original request and backend PID to determine the initiator.

## Configuration and other sources

| RPC | Current call chain | Base URL |
| --- | --- | --- |
| briskers_sync_offline_appointment_delete | BusinessGate → AppointmentSyncService.flushDeletes → BriskersApi.syncOfflineAppointmentDelete → networkSupabase | https://coensavcnuwuqaeszohb.supabase.co |
| briskers_save_invoice_mileage_out_v1 | BusinessGate → OfflineInvoiceMileageService.flush; OfflineDocumentDraftService also transfers provisional invoice mileage → BriskersApi.saveInvoiceMileageOut → networkSupabase | https://coensavcnuwuqaeszohb.supabase.co |
| briskers_issue_document | JobDocumentScreen._preparePdf → BriskersApi.issueDocument → networkSupabase; older server payment routines also call issue_document internally | https://coensavcnuwuqaeszohb.supabase.co |

Both main Flutter startup and the headless photo worker initialize the same constant in `lib/core/supabase_config.dart`. No alternate SupabaseClient constructor or other project URL was found in runtime `lib/` source. The independent Cloudflare receipt endpoint is intentionally separate and unchanged.

All **13 deployed Edge Functions** were inspected: none references any of the three incident RPC names. This rules out direct named calls in those deployed source files, not arbitrary future deployments or indirect calls. The only `cron.job` entry is the existing recurring-expense processor at **5 minutes past each hour**, not a minute-by-minute RPC retry scheduler.

Photo WorkManager tasks already honor saved Force Offline and use a separate bounded photo-upload queue. Existing bounded read/bootstrap retries were inspected; they do not invoke the three incident mutations. Ordinary shared outbox uploads, recurring bundle uploads and Owner retirement mutations receive additional durable protection in this repair.

## Server repair — DEPLOYED

Migration `20261106131501_nonretryable_business_conflicts` was applied November 6 at approximately **13:15 UTC / 7:15 AM America/Chicago**.

All **27** reviewed public Briskers functions using custom 40001 raises now use **PT409**, producing HTTP 409 instead of a serialization failure. Every version check, exception message, permission check, idempotency ledger and financial operation remains unchanged. The patch checks exact original or already-patched definition hashes and rejects unexpected drift atomically. CREATE OR REPLACE preserves function identity, owner and existing grants.

Post-deployment catalog verification matched **27/27** expected definition hashes and found **zero** remaining custom 40001 occurrences in public/briskers function bodies. PostgREST still had **two idle connections**. The inspected unified-log window **13:15–13:20 UTC** returned no entries containing 40001 or PGRST003. This is a limited offline baseline, not online acceptance.

No production shop records were inserted, updated or deleted; no shop RPC was exercised with test mutations. No restart, device reconnection, reinstall or app-data clearing occurred. Security-advisor categories/counts were unchanged; existing advisories were not altered by this incident fix. Health advisory check returned no findings before deployment.

## Application protections

- `sync_replay_fence.dart`: independent additive SQLite ledger, committed before transport. One active request per business/request identity across workers. Conflict and retry state survives service recreation and app restart; caller-side outbox resets cannot bypass it.
- Returned 40001 and PT409 are terminal conflicts. Existing stale outbox error histories are held before sending. Payloads, stable operation IDs and base versions remain intact.
- Transient timeout, socket, PGRST003 and selected temporary service failures use 30/60/120/240-second exponential delays plus 0–25% jitter. Maximum five attempts per unchanged failed request, followed by Owner-review hold. Unknown business failures are held rather than guessed retryable.
- Interrupted committed claims are held for reconciliation instead of expiring a lease while an uncertain mutation could still be running. No automatic release method bypasses this hold.
- Force Offline is checked before ledger work and again immediately before transport. Resume no longer clears the foreground retry deadline.
- Shared LocalJobQuarantine replay keeps its existing receipt and revocation checks. Customer/vehicle uploads also use the fence; the three incident API entry points protect direct callers.
- Recurring bundles use stable SHA-256 request identities instead of generating a new operation token for each retry. The fence includes response validation and local acknowledgement. No recurring schedules or occurrences are discarded.
- The production Owner retirement gateway is fenced by its existing stable operation ID; its consent, snapshot and uncertainty protocol is preserved.
- Deferred mileage requests do not trigger another server-detail read through their error-recovery path.
- Existing local sync status reports held/awaiting-acknowledgement requests without exposing request payloads.

SQLite outboxes, existing payroll/receipt/attachment stores and LAN protocols are not migrated or replaced. This repair starts at consolidated candidate **5cc77de8**, which contains merged PR #430, receipt integration and newer Tasks/Payroll restoration. No UI redesign or separate APK is supplied.

## Automated verification

Passed locally, without production traffic:

- Isolated PGlite: 27-function atomic correction, definition-drift rejection, safe rerun, four actual incident conflict paths, denied permissions, unchanged function OIDs/grants/security/settings, unchanged synthetic records and rolled-back deletion operation insert.
- UI action audit: 92 screens, no known unfinished action placeholders.
- Candidate-gate tests: 41 passed.
- APK certificate-parser tests: 10 passed.

Flutter tests in PR #437 cover both conflict codes with 1,000 attempted triggers per code; timeout/socket/PGRST003/503 retries with persisted jitter and five-attempt caps; concurrent triggers; Force Offline; pre-upgrade queue/payload retention; healthy recovery; overlapping synthetic devices; and a file-backed SQLite restart including an interrupted claim. Recurring regression covers repeated conflicts across recreated workers. Existing full-suite tests provide payment/idempotency, LAN, payroll, receipt and numbering coverage. Exact-head CI results must be recorded before merge/release.

Local Flutter verification was blocked by automatic approval review when tool initialization attempted a cloud metadata endpoint. Flutter verification uses GitHub Actions instead. No metadata access was bypassed.

## Remaining acceptance and operational restrictions

All shop devices remain Force Offline. Do not install a partial APK, clear app data or re-enable sync based on the server patch alone.

After exact-head analyzer/regressions and Android/iOS checks pass, integrate this repair into the consolidated candidate without overwriting newer work. Physical controlled testing requires explicit Owner authorization: install over the existing app on **one Owner device**, verify retained local data, enable sync only there, and observe request rate, 409 conflicts, pending queue progress and PostgREST connections. Repeated stale requests must stop after one returned conflict; other operations should progress. Restart/reconnect that device and verify held operations stay held and payments are not duplicated. Only add devices after stability is demonstrated.

Held conflicts, exhausted attempts and interrupted mutations require explicit reconciliation with authoritative server state before retry. They are intentionally not automatically reset. General-purpose Owner conflict-resolution UI is not introduced by this stability patch. Never “resolve” a conflict by deleting legitimate shop data or regenerating payment operation IDs.

Support should confirm availability of a PostgREST 16 upgrade, which fixes the platform retry bug. The code correction protects these custom business conflicts on the current version; it does not constitute a platform upgrade or prove the original initiating device identity.
