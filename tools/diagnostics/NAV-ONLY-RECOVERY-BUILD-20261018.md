# Emergency navigation-only signed Android APK

Release source: verified navigation-only fix commit 811f3c5c7a034a2b426a0ecddcd9fe8867fd9b12; the only release branch differences are the signed-APK CI whitelist and this build request.

Includes:
- Shell module navigation dock on invoice details
- Focus-aware module dock even if Android reports a stale keyboard inset
- No duplicate floating + button on customer Overview
- Numeric Tax dialog focus cleanup on Cancel and Save

Excludes:
- Experimental global StaleKeyboardInsetGuard (failed tests in separate PR)
- Offline invoice Tax Save (issue #169, still preview-only)
- Broader viewport/content clipping fix (issue #217, still being investigated)

Safety: no financial record writes or Supabase changes by this build, no forced sync. Owner should install over b2303, never uninstall/clear data, remain in Force Offline and verify navigation before any other testing. Protect invoice #6349 pending Cash $174.80, Janet #6348, Sara #6345.

Release gate: Flutter analyze and tests; full APK compile; package/version; permanent Briskers release signing certificate and verification manifest. Do not deliver if any gate fails.
