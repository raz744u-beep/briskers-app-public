# Briskers 2312 Force Offline Employees spinner hotfix — signed Android QA

Source: draft PR #230, based on b2312 (release/offline-roster-invoice-refresh-20261018).
Owner's actual phone: Auto Employees list passed, Force Offline Employees remained spinner at 12:15 PM Oct 18.
Cause: employee_roster_cache._key read auth.currentUser through networkSupabase, whose network guard intentionally throws in Force Offline. _read evaluated key outside try, EmployeesSettings._load left _employees=null forever.
Fix: use local supabase.auth.currentUser session without network, catch key errors, bound preferences reads and friendly offline state.
No changes to financial/server billing, customer records, employee table, employee compensation, RLS, or Job deletion. No phone synchronization or mutation by this build.

Release gate: Flutter Android analyze+tests, iOS compile, permanent signing cert matching b2312 and package com.briskers.briskers_app, increment versionCode, install OVER existing app without clearing data.

One-step phone test: keep Force Offline, open Settings -> Employees, screenshot saved READ-ONLY roster with five names, no pay/SSN. If no saved roster, show offline unavailable rather than permanent spinner. Do not edit any live records. Then assess Job/Appointment assignment screens individually.
