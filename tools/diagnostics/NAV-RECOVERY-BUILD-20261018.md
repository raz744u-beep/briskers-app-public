# Briskers navigation recovery signed Android build

This branch contains the draft PR #216 navigation/viewport repairs on top of signed b2303 payment code.

## Fixes included
- Customer Overview: hide duplicate floating + while keeping the main + New action.
- Invoice details: restore module navigation dock from the Shell, without duplicating the list dock.
- Module Dock: stale Android keyboard height without focused EditableText no longer hides all navigation.
- Main Shell, invoice list, invoice detail tabs and customer detail: restore full viewport when the previous keyboard height remains erroneously reported after focus leaves.
- Invoice tax dialog: unfocus numeric keyboard on Cancel/Save.

## Explicit exclusions / QA
- Offline invoice Tax **Save remains preview-only** and is not corrected by this emergency navigation build (issue #169).
- No database migration, payment write, sync, finalization, purge or removal.
- Owner b2303 install must be upgraded in-place; no uninstall, app storage clearing or manual sync.
- Phone starts in Force Offline; test main dock and scrolling first, preserving Barbara #6349 cash receipt and Janet #6348 pending receipt.

GitHub Android pipeline must pass Flutter analyze, entire Flutter test suite, signed APK certificate, APK identity and artifact verification. Build only; no deploy to user device.
