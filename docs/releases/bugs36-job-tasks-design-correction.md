# Bugs 36 — missed job-specific Tasks layout

Owner screenshot after b4653 showed J-56 still using the older tinted, fully outlined cards and a tall stack of expanded actions. The handoff changed the shared/global cards but missed `JobScopedTasks`, which has its own presentation. The previous release's claim of complete design coverage was too broad.

This correction applies the approved white compact cards and colored left edge to the existing job-scoped route, retains status colors/icons and actual assignment hours, and places overdue/priority beside the action without squeezing the title. Expanded details show formatted work dates and one paired Edit Task / Edit Assignment row. Mark All Done shares the count row. The job header includes the vehicle icon; creation buttons use the existing muted teal style.

Long press retains Edit Task, Edit Assignment and eligible Mark Done, and now holds the existing protected historical wage reconciliation and unpaid-history review actions. Those invoke the same Owner confirmation and repository methods. Split mechanics retain individual progress actions. Paid wages remain protected, while text/date edits remain available. No records, schemas, dates, assignments, payroll calculations, or invoice amounts are migrated or modified by this presentation change.

Verification adds a phone-sized J-56 reproduction covering compact dimensions, white surfaces, one-line collapsed text, paired editing, long-press separation, paid protection, and screenshots of collapsed/expanded cards. Existing focused assignment/date/bulk-completion checks and analysis passed. Required exact-source release checks and signed emulator install-over must pass before delivery; the upgrade baseline is the delivered b4653 APK.

Physical Owner-phone acceptance remains separate from synthetic emulator/widget checks.
