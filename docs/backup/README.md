# Offline folder backup and restore

This candidate carries PRs #490 and #511 forward from the `fix/bugs38-consolidated` integration baseline (`3336de5fc0ec20bf0c018cd4749e11386339595b`). It also includes the Expense IQ photo import and offline receipt access from the subsequent Note 9 candidate.

## Owner operation

On Android, Settings > Backup & Restore > Choose backup folder. Select a writable folder in Internal storage. Create Backup saves a unique dated folder under Briskers_Backup/Backups. It streams originals and the installed universal APK, snapshots SQLite with VACUUM INTO (including committed WAL records), saves non-secret Briskers preferences, and writes backup-info.json last. The manifest records file sizes/SHA-256, schema, table counts, app version, and warnings. During export, the screen shows completed copies, transferred bytes and bytes whose SHA-256 matches the snapshot. The bar includes bytes written and bytes read back. Android publishes the completion manifest only after all payload checks and the staged manifest check pass. A failed dated folder can remain without a completion manifest. Earlier snapshots are retained and never automatically deleted.

Point OneSync or another folder-copy utility at Briskers_Backup, and verify a dated folder has reached a second device or private remote storage. A verified local copy does not prove the remote copy is complete. Folder providers themselves may require internet; choose Internal storage for offline operation. There is no Supabase dependency or automatic enablement of device sync.

Automatic daily backups are opt-in and run while Briskers is open, checked every fifteen minutes. A missed run retries on a later open/check. Closed-app background execution is not claimed. Keep enough free space for a database snapshot, originals, APK, and external dated copy; no existing backups are deleted on failure.

The Backup & Restore screen displays Expense IQ original-photo import coverage separately from checksum success: an absent, mismatched or incomplete import status does not prove that an external Expense IQ photo folder was backed up. The status is informational, not a claim that the saved snapshot is corrupt. Check each device's original folder independently, including unlinked photos, and keep source originals until inventory and off-device backup are verified.

A backup covers records and files known on this device. Missing referenced local/SAF originals and known cloud-only attachments produce explicit incomplete warnings. No network download is attempted. A missing database or settings file, a failed checksum, or a transfer failure prevents completion. Split APK installs produce a warning to keep the matching installer separately. Authentication tokens, secure storage, Owner enrollment, device identity, and gateway credentials are not exported as preferences. Re-enter credentials on a replacement device; complete Owner sign-in/setup before invoking restore there. No claim is made that unknown or never-downloaded server history is present.

## Restore

Choose a dated folder containing backup-info.json. The app imports into private staging, checks all file hashes, verifies SQLite integrity/foreign keys/table counts/business/schema, and creates an isolated restored copy. It rewrites exact original-file paths, including nested JSON and outbox payloads. The separate confirmation schedules replacement on next launch, before document caches, network initialization, or background scheduling. Cancellation before confirmation changes no live data. The app must be fully closed/reopened; returning through Android Back alone is not a restart.

On startup, a database safety snapshot is retained under application support / backup-safety. Existing original files are not deleted. Live table replacement uses one SQLite transaction; operation/payment IDs, paid flags, historical hours, and queues are copied, never replayed through payroll or payment APIs. A transaction marker allows a crash after commit but before preferences to complete without applying the restore again. Device-specific auth and folder grants remain on this device. Connection mode is forced offline after restore. Cached findings photos can resolve their copied originals across changed private-storage prefixes; their deterministic identities are carried into subsequent backups.

Restore is deliberately restricted to matching managed schema/table definitions. Lazy runtime tables first created after the backup are removed as part of the replaced state and can be recreated by the app. Upgrade migrations or data merges are not part of this routine. It is a replacement backup restore, not two-way sync. A schema mismatch fails before live replacement. Restoring an incomplete backup requires the visible warning confirmation.

## Physical-device acceptance

Use a build approved by the Owner and keep each device in Force Offline during these checks.

| Device | Test |
| --- | --- |
| Galaxy S26 Ultra | Create a backup only. Use a writable folder in Internal storage, confirm real counts and bytes through verification, and confirm the new dated folder contains `backup-info.json`. Copy the entire dated folder to another private storage location and compare the saved copies. Review any missing-original warnings. Keep the live database untouched by restore. |
| Galaxy Note 9 | Use an isolated Briskers installation with synthetic receipts and an Expense IQ test photo folder. Import old originals alongside newer app photos. Make a large backup. Interrupt a new copy and retry. Revoke and regrant the test folder's permission and confirm the earlier completed folder stays intact. |
| Galaxy S12+ tablet | Use an isolated installation with synthetic records. Open the copied synthetic dated folder, verify it, then restore and reopen. Check photos, documents, signatures, estimates, paid invoices, payroll IDs and queued operation IDs. Corrupt a separate copy and confirm it fails verification before any replacement. |

After the isolated restore, make another backup to verify that restored paths and payment identities persist across generations. Keep the original Expense IQ folder and the earlier backups throughout testing.
