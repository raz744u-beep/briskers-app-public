# Briskers open defects — Work Performed / Visit History

## JOB-005 — Findings exist but Work Performed and Visit History are empty

**Reproduction:** Debbie Kohl, invoice 6321, linked completed job MB-6321.

**Verified in Briskers Dev:** Customer complaint: "The customer said the car was overheating." A saved, resolved Finding says "The thermostat is defective, and the hoses are leaking." The linked job has zero `briskers.job_visits` rows. The Finding is not lost, but is deliberately separate from Work Performed. Do not infer repair activities or historical service dates from that Finding.

**Root cause:** The Job Detail Work Performed editor refuses to open if `job.visits` is empty, and it requires the `edit_work` capability, even for office roles. The offline work service similarly rejects saving without a pre-existing `local_job_visits` row. The server update RPCs also reject jobs without a visit.

**Required repair (not implemented in this diagnostic-only change):**
- Owner and secretary can start Work Performed on an authorized job with no visit.
- On the first save, create an authenticated, audited, properly linked visit (not a fictional historical visit). Preserve entered text; store actual entry time separately from service date.
- Make repeat saves and interrupted retries idempotent and safe, including Force Offline queueing/conflicts.
- Synchronize the visit back into Work Performed and Visit History.
- Preserve original MobileBiz job, Findings, invoice lines/payments and any earlier visit records; never copy Findings into Work Performed automatically.
- Add backend permission tests, sandbox tests for no-visit save/retry, and a real-device test with MB-6321.
- Do not allow a generic visit to change the job's completed status or unexpectedly reopen invoice 6321.

**Diagnostics:** JOB-004 reports completed jobs lacking visit records; new JOB-005 flags jobs with saved Findings but no corresponding visit and explains why Work Performed editing is blocked. These checks are read-only.

**Status:** Tracked for follow-up implementation. This build adds diagnostics only, not automatic visit creation.
