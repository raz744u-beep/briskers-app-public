# Signed Android navigation and sorting recovery build — 2026-10-18

Source PR: #216 (draft / unmerged).
Verified source commit: c2ed91273dba83a61e3134e5a811aacab38d1a00.
Flutter Android Diagnostics run: 39098105841 — SUCCESS, 809 tests passed.
iOS compile run: 39098105840 — SUCCESS.
Release branch: release/navigation-sort-verified-20261018.
Release branch only adds the Android CI trigger whitelist and this immutable manifest; financial/runtime code matches the verified PR commit.

Requested: permanently signed install-over Android APK, version code 1000 + GitHub Actions run number (must exceed installed b2303), Briskers release certificate SHA-256 82075a34ef748541a270af4172dd3ddc37f3e464d9ac9f20eeef7f40a029ff08.

Contains: navigation/keyboard inset recovery, invoice detail dock access, customer Overview floating action correction, newest-first Jobs and customer recent Invoices/Estimates.
Does NOT contain: offline invoice Tax Save (#169); no Supabase migration, financial operation, or automatic payment reconciliation.
Mobile acceptance must initially remain Force Offline; preserve Janet #6348 queued payment and Barbara #6349 existing pending payment.
Do not uninstall, clear application storage, manually sync, finalize, or recreate pending receipts.
