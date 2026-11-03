# Owner Delete Job client

The Owner Job menu includes confirmation and a durable deletion request. The app rechecks the confirmed selection, preserves pending work, and resumes reconciliation after restart or connection loss. Protected financial history cannot be removed through this action. Document numbers are not automatically recycled.

The client supports a bounded set of unused Jobs and eligible linked draft invoices. Jobs with payments, meaningful work, imported history or other protected dependencies may be refused. Recovery requires an administrator; there is no in-app Undo.

## Activation status

The required server update has not been deployed. Before activation, the client reports that the server update is required. This APK does not by itself enable deletion against the current server. Production deployment and any assistant-executed deletion require separate authorization.

Backend implementation, database fixtures and detailed deployment material for this feature are maintained privately and are not included in this repository. Public tests use synthetic identifiers and exercise the app-facing contract. Backend and financial validation remain part of private release acceptance; they are not replaced by the public client checks. They do not prove deployed authorization or real-device behavior.

## Verification

Local Flutter analysis and 733 tests passed for the client implementation. Hosted Android, iOS compilation and diagnostics must pass for the exact published commit. Device acceptance, safe rollout to all affected devices and backend activation remain separate requirements. No live records were deleted by this work.
