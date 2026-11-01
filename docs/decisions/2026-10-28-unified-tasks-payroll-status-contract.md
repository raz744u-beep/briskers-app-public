# Unified Briskers Tasks/Payroll TEST status contract

Date: October 28, 2026  
Status: **Owner-approved workflow, implementation in progress**  
Source tracking: GitHub issue #365

## Main display

Jobs and Invoices expose only **Open** or **Closed** as their *main* status. Do not add Pending Close, In Progress, Waiting Parts, or Needs Recheck as other main pills. Those remain distinct internal workflow/attention attributes as necessary for backend migrations, filtering and auditing.

The main display is automatic, not a manual status picker. Showing Closed requires a server-acknowledged close; local payment entries, completed task portions, a $0 balance, and queued operations cannot certify closure.

## Payment and completion

Payment information is distinct: **Unpaid / Partial / Paid** according to *finalized* payments. Unfinalized receipts remain visible as entered/unfinalized in Payment, but do not count as posted/finalized money. Never treat a zero balance that includes pending receipts as confirmation of closure.

After full payment finalization the Owner may choose **Keep Job Open** or **Complete Job**. Keep Job Open leaves Job and Invoice main status Open with a separate Paid indication; tasks unchanged. Complete Job requests closing both when approved financial/work preconditions are met, but either main Closed pill appears only after authoritative backend confirmation. An unpaid Job may have all work tasks Done while still being Open.

Job task progress: **Not Started → Start → In Progress → Done**, operated directly in Service Tasks/Job Detail, no manual Edit→Status path. Starting work may update activity internally but does not close a Job or invoice. All service tasks finished may show **All Tasks Done** separately.

Shared task: each assigned mechanic can mark only their own portion Done. The aggregate task is Done only once *all* mechanics are Done. Use individual and overall green checks, no strike-through. Reopen/Undo Done affects work progress only; it does not reverse payments or previously credited payroll hours. Rechecks are new work with old paid work preserved.

## Payroll

Only Owner (or explicitly authorized commercial role in later edition) selects completed, unpaid credited mechanic hours, approves weekly payroll, adjusts totals with audit, makes payments/advances, and exports history. Partial Job payments allowed. Frozen already-paid allocations must never become selectable again. Separate operational Payroll tab from past Reports/Payment History. Test-only money and fixtures are **never migrated** to shop live ledgers.

## Integration and release protection

Do not merge synthetic `lib/tasks_lab_main.dart` wholesale. Port isolated task/payroll policies and UI to existing tenant-scoped shop Job, Invoice, Customer and Employee records with durable offline-first outbox. Preserve every existing production payment, Job history, ID and attachment. Integrate current bug-fix candidates only after individual verification; specifically replace PR #364's interim *visible Pending Close* behavior with this approved main Open/Closed contract.

Acceptance requires owner preview of integrated UI **before another APK**, independent Note 9 TEST shared-task check, full Android/iOS automated tests, and a separate integrated S26 TEST candidate. No production merge, schema write or real payment action is authorized by this document.
