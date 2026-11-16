# Briskers Android emergency UI recovery candidate — 2026-10-19

## Scope
This is an isolated source-based recovery candidate, **not confirmed to be exact b2318**.
Base: `release/payment-actions-invoice-dock-20261018`, not stale `main`.
Preserve working modern `BriskersModuleDock` bottom navigation, screens, routes, module permissions and live-data safeguards.
Base already explicitly pins `shared_preferences_android: 2.4.28`, previously associated with successful Samsung startup recovery.

## Safety and acceptance
- Build through permanent-key GitHub Actions, requiring versionCode > b2321 and expected certificate SHA-256.
- Install only **over** the existing app; never uninstall/clear app data, outbox, local schema, pending appointments, expense photos or financial caches.
- Start on actual Samsung S26 Ultra; validate modern dock and menus, Jobs, Customers, Estimates, Invoices, Expenses, payments, Offline + Sync settings before business use.
- Never claim the modern UI APK is phone verified just because CI is green.
- The newer invoice Expenses tab and finding actions from stale-main PRs #242/#244 are NOT yet included in this base. Port separately after safe recovery, not at the expense of working navigation.
- The user believes b2318 was the last working install. Exact 2318 source commit still needs verification. This candidate uses later Oct 18 release source instead and is not proof of exact b2318 equivalence.
