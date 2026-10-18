# QA release — Appointment employee role picker, Oct 18 2026

Source: PR #233, based on signed Briskers b2316.
Purpose: show the same role-specific icons/colors in **Appointment Edit & Create** employee dropdowns as Employees and Jobs. Existing offline roster, selected employee IDs, and appointment save logic unchanged.

Phone test: install over current signed app (same package/signing cert, strictly newer build), **do not uninstall or clear data**. Stay Force Offline. Open an existing appointment, tap Planned mechanic, verify blue Mechanics, orange Porter, navy Owner, purple Secretary; choose Cancel/Back without saving.

Separate issue #234: existing Oct 1 test appointment may have broken local Job/customer/vehicle dependency. Do not edit/delete this appointment or associated records; read-only diagnostic later. Avoid using it for saving an appointment assignment.
No live DB updates or financial changes authorized by build.
