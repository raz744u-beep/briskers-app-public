# Briskers Android release candidate — 20 October 2026

## Purpose
Owner requested an installable signed APK to check the consolidated stability fixes on the normal Samsung phone. This is a **phone QA candidate**, not a declaration that every backlog item is complete.

## Source
- Base: recovery/oct19-modern-ui-b2322-candidate, preserving modern BriskersModuleDock and shared_preferences_android:2.4.28
- PR: #250 (fix/oct19-b2322-stability-consolidated)
- Never release from stale main or merge unrelated work to produce this APK.

## Included (requires device acceptance)
- Expense detail first paint before slow enrichment/attachments; permissions still fail closed
- Expenses transaction cloud state no longer inferred from cache/server list swap
- Invoice linked Expenses fourth tab with offline cache path
- Findings Edit/Resolve/Delete and targeted invoice-banner refresh
- Avoid identical remote redraws in Estimates/Invoices
- Current invoice labor read-only summary in Invoice Notes and Job Work Performed on drawer open; editable manual notes stay separate.

## Known unresolved / not to claim complete
- #175 immediate mutation-triggered synchronized persisted Work Performed across all views, devices and offline remains unproven; no rewriting manual visit notes from invoiced/planned labor. Not a blocker for a **limited stability phone QA candidate**, but a blocker for claiming the feature complete.
- #251 reports b2323 section-navigation delays, intermittent expense spinner, and sync badge flicker. Code fixes need Samsung validation. Passing automated tests does not resolve this report.
- #116 Owner Delete Job v3 is not deployed; no destructive delete tests on live records.
- #239 appointment operation-key UUID issue remains separate and unsynced queue items must be preserved.
- Payroll and Owner Dashboard are separate tracks.

## Safety and acceptance
1. Android workflow must pass analyzer, Flutter tests and keystore/certificate verification.
2. Signed APK must have package com.briskers.briskers_app, SHA256 certificate as enforced by workflow and build number greater than installed b2323.
3. Update over existing installation; **do not uninstall or clear storage**. No reset of customer, invoice, payment or unsynced records.
4. Owner to validate startup, bottom dock, all main modules, expense first paint/cloud icon, invoice Expenses tab, finding actions and edit/payment behavior, plus offline/online return.
5. If phone QA fails, stop rollout; do not mark candidate stable.
