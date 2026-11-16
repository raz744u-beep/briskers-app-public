# Briskers Android offline tax-save recovery — 2026-10-18

Code source: draft PR #221 head e12b6b7f8e192a537f518a7a718b9e685c3ecf74.
This release branch differs from PR source only in CI branch trigger allowance and this manifest.
Android diagnostics run #39105877800 **SUCCESS: 820 tests passed**.
iOS compilation run #39105877914 was pending when release packaging was requested; confirm before phone delivery.

Purpose: Fix invoice #6349 Force Offline tax Save (9.25% to 9.75%). Local preview changes invoice tax $14.80→$15.60 and total $174.80→$175.60; one durable SQLite queue operation stores owner intent and server version precondition. Existing pending cash payment $174.80 remains untouched, and financial finalization is blocked until queued tax change retires. Ambiguous server outcomes are fenced for manual review rather than automatically resent. No new server migrations or real customer data writes in this build process.

Signed APK source identity / version verification required: com.briskers.briskers_app, v0.10.9 build number > 2307, certificate SHA-256 82075a34ef748541a270af4172dd3ddc37f3e464d9ac9f20eeef7f40a029ff08.
Phone acceptance: Install OVER existing build without uninstall or clearing data. Verify Settings > About version code and keep Force Offline. Read-only opening #6349 and entering tax editor, then one explicit owner save, app restart proof. Do not sync, finalize, re-enter, or delete original Cash payment. Barbara's invoice and Janet Williams #6348 remain protected.
