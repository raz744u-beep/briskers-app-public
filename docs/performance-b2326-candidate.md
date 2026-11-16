# Build 2326 performance candidate

This isolated draft continues issue #251 from PR #254 at
`0e9519bbde88623fdbb27f1eb9995838aac14e57`. It preserves the modern PR #250
baseline and is not based on or merged into `main`.

## Changes

- **Navigation:** lazily retain the visited Estimates, Invoices and Appointments
  modules. Returning to them preserves their filters and scroll position.
  Hidden modules cannot receive focus or run tickers. Business/role changes
  reset the retained state. Other modules retain their previous lifecycle.
- **Appointments:** show local query results before synchronization and dashboard
  work. Changing filters/search does not repeat queue replay, remote pull or
  dashboard work. Shared refreshes serialize synchronization; mutations request
  a fresh trailing pass. Check-in recovers the durable local job ID if an
  already-running refresh applied the queued operation. Force Offline can show
  local data even while an older network operation is stalled.
- **Estimates and invoices:** retain rich visible rows during background refresh,
  coalesce overlapping work, sort each changed snapshot once, and build cards
  lazily. Compare every field structurally rather than serializing whole lists
  to JSON. Skip identical index/style writes. Preserve invoice draft grouping,
  latest-number-first ordering, payment amounts and statuses. Returning from
  another module requests fresh state, including a trailing pass when an older
  refresh is active. Offline entry rereads local data and receipts; retirement
  hides affected rows immediately, independently of network success.
- **Expense Detail:** render the supplied preview immediately, then hydrate
  full local detail and authoritative remote detail independently. Auto network
  failure retains safe read-only local detail and attachments. Stale local,
  permissions, reporting and attachment results cannot overwrite another record
  or a newer server result. Permission-sensitive actions remain fail closed.
  Attachment byte reads are memoized, file checks are asynchronous, and build
  no longer starts repeated attachment prefetches.
- **Instrumentation:** emit `Briskers.navigation.first_content` timeline events
  with module, source and elapsed microseconds only. Hidden or covered modules
  cannot satisfy the measurement. This measures first visible content, not
  synchronization completion, and includes no customer data.

## Measurements

These are reproducible synthetic host measurements, **not Android device or
end-to-end latency measurements**. The benchmark reproduces the previous CPU
algorithms and compares them with the replacement helpers. It does not call
live APIs or measure network, SQLite, frame rendering or allocation counts.

Command: `dart run tools/benchmark_document_list.dart`

Environment: Flutter 3.47.7, Dart 3.13.5, Linux cloud workspace. Final run:
2026-10-20 UTC. Each operation uses 5 warm-ups and 15 measured samples; 5,000
synthetic rows and separately materialized equal snapshots prevent identity
shortcuts. Sorting uses a deterministic shuffle and verifies identical ordering.

| Operation | Previous median | Candidate median | Median reduction |
| --- | ---: | ---: | ---: |
| Whole-snapshot equality | 22.656 ms | 2.676 ms | 88.2% |
| Parse document number and sort | 113.117 ms | 44.861 ms | 60.3% |

Raw synthetic results are in `docs/performance-b2326-benchmark.json`.
Host timing varies between runs; these percentages are not app-speed promises.

Regression work-count assertions:

- 31 synthetic module entries cause 31 initial loads with the previous
  single-body lifecycle, versus 3 with retained visited modules.
- A 500-row estimate list builds fewer than 30 cards for its initial viewport,
  rather than eagerly building every card.
- Warm filtering performs no new full-snapshot sort.
- Appointment filter/search changes do not cause extra remote replay, pull or
  dashboard requests.
- Overlapping document refresh requests share work, but a post-action/entry
  pass is deliberately retained when needed for financial freshness.

Sequential online document entries still revalidate authoritative state.
This change does not claim to eliminate every full-list API download.

## Verification

Local final assembled candidate:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --concurrency=4`: **882 tests passed**.
- UI action audit: **74 screens passed**.
- APK certificate parser tests: **10 passed**.
- Fail-closed candidate CI gate tests: **37 passed**.
- `git diff --check`: clean.

New regression coverage includes local-first display, offline/Auto/online
transitions, delayed/out-of-order responses, retained filters/scroll,
payment/status refresh after navigation, latest-first ordering, retirement,
cache-write races, queue preservation, concurrent check-in, expense local
fallback, stale permissions/reporting/attachments, hidden focus/tickers and
first-content instrumentation.

The original PR #254 had Diagnostics #821 and iOS compile #552 successful on
its exact head. Those runs do not validate this new candidate. Candidate
Diagnostics and iOS checks must pass on its exact SHA before Android work.
The isolated-branch Android gate verifies that prerequisite and the current
branch head, with bounded waiting and read-only Actions access. Existing
permanent-certificate, package/version and artifact checks remain in place.
CI run links and the candidate artifact belong in the draft PR report.

## Remaining acceptance work

- No real-phone tap-to-content p50/p95 or scrolling/frame-time results are
  available yet. Capture timeline events on the candidate phone in offline,
  Auto and online modes, with representative cached list sizes.
- On the phone, verify retained filters/scroll, latest-first rows, existing
  payment/status values and expense attachment/permission behavior. Exercise
  mutations only in an approved test shop or fixture.
- The saved-data banner and synchronization warning are separate: using cached
  data does not establish that the device is offline. A recent successful pull
  can coexist with pending/failed work. The owner's exact warning requires
  device diagnostics; this patch does not claim to resolve a specific pending
  operation.
- Automated coverage uses synthetic data. No production database, live shop
  records, queue clearing, destructive migrations, app reset or phone uninstall
  is part of this work. Phone acceptance and production rollout remain pending.

## Changed application files

- `lib/core/document_list_refresh.dart`
- `lib/core/navigation_content_timing.dart`
- `lib/widgets/retained_module_stack.dart`
- `lib/screens/shell_screen.dart`
- `lib/screens/appointments_screen.dart`
- `lib/screens/documents_screen.dart`
- `lib/screens/expenses_screen.dart`
- `lib/screens/expenses/expense_detail_screen.dart`

Supporting changes are the seven regression-test files, the synthetic
benchmark, candidate-gate script/tests, three narrowly scoped workflow files,
and this report with its benchmark data. No backend SQL or credentials are
included.
