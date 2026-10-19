# b2322 consolidated stability batch — owner-requested Oct 19
**Base**: `recovery/oct19-modern-ui-b2322-candidate` (on-device startup & modern dock working). Do **not** base on stale `main`.
Scope:
1. #249 expenses transaction sync icons: distinct from income receipt coverage and attachment/photo upload; real status only.
2. #249 expense detail first paint: eliminate white spinner blocking while full transaction/permissions/report/receipt prefetch occurs; cached transaction immediately; background refresh and fail-closed privileges.
3. #240 invoice fourth Expenses tab: reuse Job Expenses/add/edit/list with permissions, offline/online, dedupe; preserve other 3 tabs and bottom dock.
4. #241 Estimates/Invoices delayed second redraw: avoid unchanged snapshots causing flicker, preserve true updates and filters.
5. #243 vehicle finding Edit, Resolve, Owner Delete with targeted findings-only banner refresh, no full invoice reload; support offline/online safely.
6. #175 automatic Work Performed from all linked invoice labor lines on labor add/edit/delete; preserve manual notes, no duplicate/stale entries; b2322 currently derives labor on opening Job Work Performed but not necessarily at invoice mutation.
7. #239 appointment invalid UUID outbox: diagnose and preserve unsynced operation; do not silently clear or delete.
8. #247 release guard: startup smoke and modern BriskersModuleDock must persist; keep `shared_preferences_android:2.4.28`.
9. Keep existing payments, invoice numbering (#6335-6340, next #6341 plus subsequent new #6341), customer records, jobs, expense transactions and synced local data unchanged.

**Release gates**: precise code review, analyzer/tests and regression fixtures, Android signed higher versionCode than b2322, certificate and package validation, iOS parity check, Samsung on-device startup and navigation verification *before* functional feature testing. Do not merge into stale main or claim APK validated from CI alone.
