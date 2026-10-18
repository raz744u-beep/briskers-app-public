# Briskers Jobs quick assignment — role icon QA build, Oct 18 2026

Source: PR #232 on top of signed b2315 release/employee-offline-role-icons-20261018.
Owner test: Force Offline Job assignment picker displays the five correctly saved employees/positions, but uses one generic gray person icon for every employee.
Fix: reuse existing employeeRoleStyle(position) in lib/screens/jobs_screen.dart; CircleAvatar role icons and role-colored subtitles match Settings > Employees and Job Detail. All assignment behavior unchanged.

Safety: no Job, employee, payroll, payment, tax, account, sync outbox, or server modifications from this build. Build with permanent existing signer, package com.briskers.briskers_app, strictly increment Android versionCode from b2315; install over existing app and never clear storage.

Phone acceptance: Keep Force Offline; open Jobs -> mechanic quick-assignment picker WITHOUT selecting anyone. Expect Chris/Kamerron blue wrench, Adam orange truck, Owner navy award, Tyrianna purple headset, with unchanged role text, Unassigned neutral. Screenshot. If passes, test actual assignment only with explicit approval.
