# Never-uploaded local Job cancellation

This is an additive local-cancellation path, separate from server-confirmed owner-deletion-3.0. No APK, deployment, production data change, or paid resource is needed to integrate it.

## Eligibility and consent

- Owner authorization, current actor, and visibility generation are checked at preview and confirmation. The generation and actor are checked again at the end of the cancellation transaction.
- Supported fresh roots: explicit stable-UUID Job creates, Quick Invoice provisional Jobs, and wholly local standalone-estimate-to-invoice conversions.
- Every selected record and operation requires positive original creator provenance. `recordNewIntent` belongs only beside fresh identity generation inside its original creation transaction. Never call it from restore, import, remapping, repair, retry, or server hydration code.
- Historical rows without this evidence require online reconciliation, even if their IDs look temporary and attempt counters are zero. Temporary IDs, a failed request, and an unavailable server do not prove absence.
- An initial standalone estimate used by a conversion must have no other local consumer. The source itself is included in the one itemized confirmation.
- Discovery refuses attempted uploads, lost acknowledgements, server metadata, unknown content/relationships, shared records/media, or scope-quarantined work. Matching only a vehicle or customer is never ownership proof.
- Preview items include distinct document kinds, document numbers when present, payment amounts/methods, and local financial amounts/account labels. Financial labels unavailable locally must be shown honestly, not replaced with an invented name or currency.
- The preview's immutable SHA-256 hash binds the exact local rows, outbox payloads, and cached content. Confirmation recomputes it in the cancellation transaction; changes require a new review.

## Dispatch and cancellation ordering

`LocalJobQuarantine.guardReplay` calls `OfflineJobPurge.recordDispatch` immediately before every request. The latter atomically checks the live outbox/fences and journals the dispatch before any network bytes are sent. Counters can be reset by old retries without erasing this evidence. Dispatch identities survive outbox removal or reinsertion under a different queue ID.

The SQL transaction either cancels first, in which case a later dispatch is rejected, or records dispatch first, in which case local cancellation is rejected. No response or timeout can turn an attempted operation into a never-sent operation.

An uncorrelated guarded write marks only pending Jobs existing at that time as uncertain. It does not poison future newly generated identities. A malformed queue payload cannot be dispatched.

## Local completion

`OfflineJobPurge.confirm` atomically persists minimal permanent typed identity fences and a minimal registration request, removes exactly confirmed local rows/outbox work, and preserves unrelated financial snapshot members. It never fabricates a verified server deletion receipt.

Preferences and app-owned media cleanup are resumable. Canonical app-root/path checks, symlink rejection, and remaining-reference checks are shared with the verified server cleanup path. External source files are not deleted. Startup resumes incomplete local cleanup. A partial cleanup is reported as pending rather than complete.

## Server registration

Send each `pendingRegistrations` result to:

`briskers_job_delete_register_local_v3(p_business_id, p_job_id, p_operation_id, p_confirmation)`

The confirmation has exactly nine keys:

- `schema_version: 1`
- `protocol_version: owner-local-cancellation-1.0`
- `scope: unpublished-local-job`
- `business_id`, `job_id`, `actor_id`
- `graph_hash`
- sorted unique `deleted_entities`
- `root_origin: job_create | quick_invoice | standalone_estimate_conversion`

For Quick Invoice, canonical `job_id` is its original operation UUID, with `quick_invoice/<UUID>` included. For standalone conversion, canonical `job_id` is the conversion UUID; the source estimate UUID and `standalone_estimate/<source UUID>` are both required. The actual source creation RPC uses that deterministic estimate UUID. There is no invented conversion idempotency namespace.

No local payloads, names, display numbers, payment amounts, or media locations are sent in registration. The server refuses registration if any identity, source, reference, or replay materialization exists. Such a refusal requires reconciliation and fresh server consent; never broaden the local consent into a remote deletion.

After a timeout, retry the identical registration operation and confirmation. Only acknowledge it locally after verifying its matching server result. Local cleanup complete and cross-device registration complete are distinct outcomes.

## Cross-device alias evidence

The companion additive `briskers_job_delete_local_origins_v3` lookup provides authoritative local origin information without changing the frozen remote3.0 receipt shape. Fetch and validate complete origin information for each tombstone operation batch before advancing its cursor or reopening replay. Persist exact alias fences before ordinary sync resumes.

Never infer conversion aliases merely from a graph containing a Job, an estimate, and a standalone-estimate operation; a normal server graph can have that shape too. The lookup must explicitly distinguish remote operations (`root_origin: null`) from local cancellations. Financial aliases must remain bound to the authenticated financial reader scope.

## Verification

- Passed locally: `python3 tools/validate_offline_job_purge_sql.py`, executing exact SQL templates for claims, immutable markers, counter-reset/replacement resistance, and provenance installation.
- Passed locally: `python3 tools/validate_local_deletion_v3_sql.py`, including existing scope/read-fence cases.
- Added: `test/offline_job_purge_test.dart`, covering local success, legacy unknown provenance, lost ACKs, counter resets, queue reconstruction, dispatch/cancel ordering, stale consent, immutable display items, Owner/actor changes, shared financial links, local quick invoice and standalone conversion, exact payment details, and malformed content.
- Dart analyzer and Flutter tests have not run in this workspace because no Dart/Flutter executable is available. Run those test-only checks in the integration environment. Do not trigger an APK/release build for this change.
