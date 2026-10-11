# Briskers consolidated Android test build

Requested October 11, 2026 after PR #87 squash merge `1b35d8a10409b76568c0da0763dce2f434abbd6f`.

This release marker triggers the existing GitHub Actions Android APK workflow on `main` after no workflow was returned for the squash merge. It does not alter application functionality, imported records or native signing. The resulting signed APK requires S26 Ultra acceptance before release completion.

Upcoming features are tracked in #89 (weekly mechanic/worker payments, owner-approved full amounts) and #90 (simple monthly pre-tax sales report).
