# Briskers consolidated APK release gate — 2026-10-10

Branch: `fix/appointment-offline-edit-queue-20261010` (draft PR #87).
As checked, 126 commits ahead of `main`, 0 behind, 39 changed paths.
15 Functional Diagnostics CI passed at run #38111358630; later run #38111433973 pending at audit.

## Conditions for a release-candidate APK
- [ ] Latest branch CI green (Flutter analyze, regression suite, Functional Diagnostics).
- [ ] Review branch diff and security implications of migration and RPC changes; preserve MobileBiz invoices and all real shop data.
- [ ] Check deployed Dev migrations against branch code and confirm no mismatched RPC versions.
- [ ] Verify end-to-end customer created offline → vehicle → appointment → reconnect; after a lost response/restart verify exactly one server row each and correct ID remapping.
- [ ] Verify appointment role policy (owner edit incl Job-linked w/o reassignment, secretary cancel/no delete), conflict tombstones and reconciliation.
- [ ] Verify owner test invoice / Quick Invoice creates exactly one Job/visit on online/offline sync.
- [ ] Validate payment entry, partial totals and balance on actual PDF before and after owner finalization without customer-facing pending labels.
- [ ] Test US-Letter print and printer-app handoff on S26 Ultra; do not assume native MethodChannel exists in generated Android shell.
- [ ] Check JOB-005 genuine first Work Performed save for missing-visit imported Job using safe test fixture; no backdated service dates or historical Finding mutation.
- [ ] Review ExpenseIQ outstanding/missing photos and preserve original Note 9 archive.
- [ ] Build signed consolidated APK only after source CI passes; then on-device acceptance, repeat with older Note 9.
- [ ] iOS Flutter shared changes tracked, native iOS project/build and iPhone tests separate; do not claim parity based on Android CI.

Status: release candidate not yet compiled. Do not mark owner acceptance complete until phone tests.
