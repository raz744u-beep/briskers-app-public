# Briskers b2480 — paid invoice exits Open without a manual refresh

**Track:** REGULAR Briskers Android candidate; **draft only**.

**Includes:** Fully finalized payments verified by the backend notify retained
invoice lists before the separate Job Complete decision. A verified fully paid
invoice is moved from Open to Pending Close immediately, preserving scope.
Only successful backend invoice closure moves the card to Closed. The event is
separate from received-but-unfinalized payment and does not fabricate money.

**Does not include:** Changing backend close authorization, automatically
closing invoices while a Job stays In Progress, rewriting real payments or
touching production data.

**Safety:** Unfinished sync/outbox payments must not be finalized offline.
Owner confirmation and server close permissions stay intact. Keep this
candidate separate from the isolated Tasks TEST package and never merge the
prototype into the regular app.

**Owner Samsung acceptance:** Finalize a real eligible invoice in Auto, choose
Keep Job In Progress, return to Open. The invoice must disappear instantly and
show Pending Close (not false Closed) until authorized close confirmation.
Repeat with Completed, partial payment, slow HTTP receipts, and existing
closed/reopened records. No manual refresh should be necessary.

**Status:** Candidate only, subject to exact-head Diagnostics, iOS,
Android artifact signing verification and Samsung testing. No production
release is claimed.
