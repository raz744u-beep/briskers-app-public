# S26 first-open local-first regression checklist (#313)

Base: signed S26 build 2423. Preserve existing private Briskers package, signer and app data. Do not uninstall or wipe data.

## Device scenarios
1. From cold start with Auto sync and network available, Customers immediately presents locally saved records (~2799), without misleading Total 0 or blocking on sync.
2. Jobs, Estimates, Invoices and Expenses render locally available records before remote calls finish; switch screens and return.
3. Turn off network in Force Offline; repeat all five modules, including offline create/edit; pending actions remain intact.
4. Simulate DNS failure, request timeout 57014 and connection abort. Preserve local lists and do not overwrite verified financial totals with partial values.
5. Open Local Database & Sync with 120+ pending operations. Paint local counts/history first and report errors independently.
6. Return to Auto mode and synchronize; locally created entries reconcile without duplicates; verify pending finding actions are not replayed destructively.
7. Invoice style-color endpoint failure must not delay invoice document results or persist stale styles over a newer refresh.

## Release verification
Require exact source-head Android diagnostics and iOS compile success; verify APK package identifier, signer certificate, build number is higher than b2423, release configuration and no uninstall prompt on S26. Maintain Note 9 test installation separately. Do not modify production database for this test.
