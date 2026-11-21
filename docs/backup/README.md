# Offline folder backup and restore

Initial source base: ac70d02a916e5e186b21ae8b78c7c3ed0fe4be57. Also includes consolidated Reports search fix 9654cd402746b94991184ac840c72f25831ed24b so that behavior is preserved. Isolated branch: feature/offline-complete-backup-20261120. Do not replace or reset the repair-groups working checkout. Integrate these commits into the final combined branch after its checks pass.

## Owner operation

On Android, Settings > Backup & Restore > Choose backup folder. Select a writable folder in Internal storage. Create Backup saves a unique dated folder under Briskers_Backup/Backups. It streams originals and the installed universal APK, snapshots SQLite with VACUUM INTO (including committed WAL records), saves non-secret Briskers preferences, and writes backup-info.json last. The manifest records file sizes/SHA-256, schema, table counts, app version, and warnings. Folder payloads are read back and hashed before the copy is reported saved. Earlier snapshots are retained and never automatically deleted.

Point OneSync or another folder-copy utility at Briskers_Backup, and verify a dated folder has reached a second device or private remote storage. A verified local copy does not prove the remote copy is complete. Folder providers themselves may require internet; choose Internal storage for offline operation. There is no Supabase dependency or automatic enablement of device sync.

Automatic daily backups are opt-in and run while Briskers is open, checked every fifteen minutes. A missed run retries on a later open/check. Closed-app background execution is not claimed. Keep enough free space for a database snapshot, originals, APK, and external dated copy; no existing backups are deleted on failure.

A backup covers records and files known on this device. Missing referenced local/SAF originals and known cloud-only attachments produce explicit incomplete warnings. No network download is attempted. An unavailable database/settings/APK or failed checksum prevents reporting successful completion. Authentication tokens, secure storage, Owner enrollment, device identity, and gateway credentials are not exported as preferences. Re-enter credentials on a replacement device; complete Owner sign-in/setup before invoking restore there. No claim is made that unknown or never-downloaded server history is present.

## Restore

Choose a dated folder containing backup-info.json. The app imports into private staging, checks all file hashes, verifies SQLite integrity/foreign keys/table counts/business/schema, and creates an isolated restored copy. It rewrites exact original-file paths, including nested JSON and outbox payloads. The separate confirmation schedules replacement on next launch, before document caches, network initialization, or background scheduling. Cancellation before confirmation changes no live data. The app must be fully closed/reopened; returning through Android Back alone is not a restart.

On startup, a database safety snapshot is retained under application support / backup-safety. Existing original files are not deleted. Live table replacement uses one SQLite transaction; operation/payment IDs, paid flags, historical hours, and queues are copied, never replayed through payroll or payment APIs. A transaction marker allows a crash after commit but before preferences to complete without applying the restore again. Device-specific auth and folder grants remain on this device. Connection mode is forced offline after restore. Cached findings photos can resolve their copied originals across changed private-storage prefixes; their deterministic identities are carried into subsequent backups.

Restore is deliberately restricted to matching managed schema/table definitions. Lazy runtime tables first created after the backup are removed as part of the replaced state and can be recreated by the app. Upgrade migrations or data merges are not part of this routine. It is a replacement backup restore, not two-way sync. A schema mismatch fails before live replacement. Restoring an incomplete backup requires the visible warning confirmation.

## Acceptance before shop rollout

- Exact-source Diagnostics, iOS compilation, and signed Android build.
- S26 Force Offline: select folder, create backup, confirm counts/files/warnings and that a second-storage copy completed.
- Isolated DEV installation with test records: select that copied folder, inspect, confirm restore, fully close/reopen, verify customers, closed invoices, individual payments, payroll paid/unpaid records, recurring expenses, receipts, findings photos, signatures, drafts, and pending operation IDs.
- Retry a failed copy, revoke/regrant folder permission, damage one copied file, and cancel a restore: previous backups and current records must survive.
- Restore again and back up again: no duplicate payments; restored cached images still open.

Physical device acceptance is required before describing the S26's data as protected or claiming a production restore has been verified. Development never reads or modifies the S26 database.

## Development verification

Twenty-five focused tests run in the matching Flutter engine passed: eleven archive/integrity/identity tests and fourteen real-schema startup/snapshot/restore tests. These cover WAL contents, payment/paid flags, signature bytes and unchanged signed JSON, URI-preserving file relocation (including customer-note originals referenced only in preferences), corrupt and missing payloads, missing-original warnings, cancelled restore, retained safety snapshot, commit/restart idempotence, and photo identity across a second backup generation. Real paid-work immutability and verified-deletion guards, plus indices and views, are preserved after restore; whole-database replacement reinstalls the backed-up definitions inside the same transaction before commit. The complete create/inspect service paths and interrupted-import retry are also exercised with native channel boundaries mocked; physical Android folder permissions still require device acceptance. The native shell wiring test and all 42 existing candidate-gate tests passed. Device filesystem permissions and installation still require the physical-device acceptance above.
