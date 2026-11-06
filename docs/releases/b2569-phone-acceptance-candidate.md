# Briskers integrated phone-acceptance candidate

Source branch: `integration/b2569-receipts-payroll-numbering-20261105`

This is a **signed testing candidate**, not Owner-approved production acceptance.

## Included
- Independent Cloudflare/OpenAI receipt recognition, Owner-only secure gateway enrollment and editable review with local expense/photo save. Explicit consent; no general Supabase synchronization.
- ExpenseIQ original photo recovery through read-only Android SAF reconnect and cached attachment fallback; no photo deletion, relinking by number alone or bulk uploads.
- Restored b2568 Tasks/Payroll screens and task assignments with Owner authority. Payment state remains guarded against duplicate and unverifiable finalization.
- Owner number reuse suggestions for released invoice/job numbers, manual editing, right-aligned financial totals.

## Required checks before installing
- Workflow compilation and Flutter regressions; package `com.briskers.briskers_app`, permanent signing certificate SHA-256 `82075a34ef748541a270af4172dd3ddc37f3e464d9ac9f20eeef7f40a029ff08`.
- Verify APK build number greater than installed b2568; check artifact hash and install-over behavior, **never uninstall or clear storage**.
- Leave Force Offline enabled; isolate sensitive pending shop records, do not reenable Supabase sync or force a background queue flush.

## Physical Samsung acceptance
1. Back up local app data through existing verified workflow; do not overwrite unsynced expenses/invoices.
2. Set Receipt AI connection using the **receipt gateway token**, not the OpenAI API key; only authorized Owner device. Verify internet-enabled independent recognition with Force Offline active; review and save exactly one sample receipt and photo locally; restart and verify no duplicate.
3. ExpenseIQ Worldpac historical photo: display original or cached copy; on SAF denied use Reconnect original photo folder, regrant and reopen after restart; no mutation to financial records.
4. Tasks/Payroll employee profile, task assignment and labor, owner verification and history; do not make real payroll test payments before reconciliation safety is confirmed.
5. Job/invoice released-number suggestions and right-aligned totals visually.

## Status
Phone testing **not yet performed**. Do not label production-safe solely on CI passing; report any failures and preserve prior b2568 installation and records.
