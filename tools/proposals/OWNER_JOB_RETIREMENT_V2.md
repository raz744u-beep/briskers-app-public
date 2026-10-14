# Owner Job deletion: guarded candidate, blocked rollout

This source is **not a migration to run**. The APK whole-Job deletion gate stays
false. No production data, J18, historical invoices, customer records, payments,
expenses, or numbering were changed.

The candidate uses data-preserving retirement markers and immutable operation/audit
records rather than physical cascades. Owner/business scope, exact confirmed
snapshot, operation-ID retry binding, immutable tombstones, and pristine native
draft invoice defenses have synthetic SQL tests. Linked estimates survive.

## Required before enabling

1. Implement and audit the deployed-schema dependency adapter. It must inventory
   all foreign keys and semantic relationships; return current linked invoices,
   preserved estimates, blocking financial/history data, versions and owners.
   Never identify child invoices from stale issue numbers or test assumptions.
2. Prove write fences across all concurrent document/payment/expense/Job writers.
   An advisory lock alone does not fence existing writers. Until then the adapter
   is absent and execution fails closed even for a function owner.
3. Integrate retirement into every server read/write/sync path. Removed IDs must
   reach all devices; new writes/replays against retired entities must fail.
4. Reuse LocalCleanupSafety before consuming tombstones. Preserve/quarantine
   uncertain pending payments and all dirty work; do not advance cursors or erase
   outboxes until resolved. Prove Force Offline → Auto, stale device and retry.
5. Present one fresh linked-record preview with exact counts and one confirmation;
   require online Owner verification. Do not queue destructive execution offline.
6. Obtain approval for backend/security deployment and complete hosted database
   integration tests before granting RPC execution or changing the APK gate.

These requirements cannot be satisfied by the legacy hard-delete cascade.
No fallback to that RPC, number reuse, or live deletion is authorized here.

Retained entity rows preserve recovery evidence; an append-only restoration event
and its read/write reconciliation are not implemented by this candidate.
