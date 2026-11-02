# Bugs 13 signed Android QA build request — 2026-10-20

Owner explicitly approved building the next regular Briskers APK for install-over testing on the main Samsung phone, then building the separately installed offline Tasks TEST package for the secondary phone.

Build rules:
- Source is modern PR #263, not stale main.
- Require exact-push-SHA Briskers Diagnostics and iOS Compile pass via existing gated Android workflow.
- Permanent Briskers signing certificate and com.briskers.briskers_app identity, versionCode above installed 2327.
- Do not merge PR, deploy SQL, clear data, uninstall an app, or touch production records.
- Validate artifact APK hash/signing, then provide a direct download and a clear included/deferred list.
- Next separate Tasks TEST build runs only after this regular build is confirmed.

This is a trigger-only source-note commit. No production application logic changes.
