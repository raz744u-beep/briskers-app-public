# Customer payment category correction — #293

Prepared and tested for review only. Nothing in this folder has been deployed;
no hosted financial records have been changed.

The original RPC was inspected read-only on 2026-10-22. The guarded patch in
`tools/review/customer_payment_category_default_REVIEW_ONLY.sql` adds the exact
shop's unique active Customers income/revenue category at the existing INSERT.
It preserves permission checks, allocation math, financial amounts, payment
methods and the existing idempotency replay path. Missing/ambiguous category
fails atomically. Existing RPC identity and ACL are preserved. Unexpected source
fingerprint stops installation. Reapplication is a no-op.

The separate preview and repair files require an explicit business UUID. Preview
returns count and a fingerprint of transaction ID/version/target category. The
repair requires both reviewed values, skips nonblank categories, checks protected
fields and allocation snapshots, and defaults to ROLLBACK. It outputs a minimal
nonfinancial audit manifest. A reviewer must approve an audit destination and
explicit commit before any real repair. No new financial transaction is created.
Database row version/update timestamp triggers may advance metadata on UPDATE.

Run synthetic tests with Node 20+: `npm ci --ignore-scripts` then `node run.mjs`
in this directory. PGlite 0.5.9 is pinned in the lockfile. Tests use an isolated
in-memory schema and never connect to hosted Supabase. They cover four method
IDs, exact customer/date/amount/method retention, same-operation replay,
allocation conservation, tenant category lookup, default rollback, category-only
repair, missing category failure, denied permission and no duplicate rows.

Remaining deployment acceptance: run against a full isolated current schema to
cover existing financial audit/constraint triggers, ambiguous category failure,
fee reporting and concurrent posting/repair, then approve backend deployment
separately. These fixtures do not replace that integration review.
