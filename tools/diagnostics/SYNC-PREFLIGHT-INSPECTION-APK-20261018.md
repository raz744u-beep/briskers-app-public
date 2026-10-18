# Briskers read-only sync preflight signed APK request — 2026-10-18

Source branch: fix/sync-preflight-job109-manual-financial-20261018
Draft PR: #226; tracking #225

Purpose: allow Owner phone to inspect queued Job admin operation #109 while staying in Force Offline. NOT a prompt or authorization to synchronize, finalize payments, delete records, or process any outbox.

Code included:
- Owner-only local preflight for job_admin: Job details, queued flags, linked documents and dependent Job creation
- Manual Sync Now replay stages ordered invoice tax -> received invoice payment -> existing pending-payment correction
- Force Offline manual-sync block and truthful partial result if operations remain
- Concurrent in-process invoice tax replay single-flight / atomic claim

Source of truth for code and test status: Draft PR #226 and GitHub Actions.
Requirements before installing: signed release certificate matches prior Briskers APK; package com.briskers.briskers_app; higher versionCode; install over current app without uninstalling or clearing data.
Required phone acceptance FIRST: remain Force Offline, Settings -> Local database & sync -> Pending operation details #109; screenshot new Job audit; no Sync Now/Auto.
No production SQL or customer accounting writes are part of this build request.
