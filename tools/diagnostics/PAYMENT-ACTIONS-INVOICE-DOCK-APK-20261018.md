# Briskers payment action and invoice detail dock signed APK — 2026-10-18

Source draft PR #222: commit 98d4196cd87ebcd0aa38a5eecddfe6269ae6e72a.
Android Diagnostics: GitHub Actions run 39110144636 SUCCESS, 827 tests passed.
iOS compile run 39110144744 must PASS independently before owner delivery.
This release branch contains no runtime source changes after the reviewed PR commit; only workflow branch whitelist and this build request.
APK versionCode = 1000 + GitHub run number, must exceed installed b2308, permanent cert SHA256 82075a34ef748541a270af4172dd3ddc37f3e464d9ac9f20eeef7f40a029ff08.

Includes:
- Pending payment row can be tapped or pencil pressed, instead of hidden long-press-only menu.
- Authorized owner/office/secretary can edit amount/date/method. Owner alone sees Delete; only never-submitted local receipts can be discarded offline. Server-backed Delete requires verified online, owner-only server endpoint. No finalized payment deletion.
- Prior v3 cached server pending receipts without payment row_version can be edited offline with original baseline and pristine server version guard at future replay, preserving UUID; unresolved offline tax correction blocks payment sync until tax acknowledged.
- Invoice detail bottom dock uses one physical safe area; removes extra blank area below bar.
- Finalize Received Payment disabled while offline tax correction pending.

NO backend financial mutations, tax replay, manual sync, payment delete, or finalization permitted as part of build.
Phone install-over only (no uninstall/data wipe); keep Force Offline, protect Barbara invoice #6349 one Cash receipt originally $174.80 (actual $175.60 customer paid), Janet #6348, Sara #6345.
Owner phone acceptance required before marking feature complete. Do not automatically sync or finalize anything.
