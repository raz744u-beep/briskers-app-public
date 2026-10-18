# Briskers Appointments compact filter layout QA — Oct 18, 2026

Source draft PR #235, based on signed build b2317 (which already contains the latest role-picker changes).
Owner asks to merge five Schedule filter buttons into one line.
User-facing filters: Today (all today's statuses), Upcoming, Past, All. Today replaces both old confirmed-only Today and All today; internal confirmed-today repository counting remains unchanged.
UI: four equal-width ChoiceChip buttons in one Row, FittedBox labels, existing blue styling; compact on phone, no second line.

No business record changes, appointment mutations, dependency cleanup, customer edits, financial actions, or server updates in this build.
Install permanently signed APK over existing Android version b2317; never uninstall/clear local data; keep Force Offline for initial visual QA. Phone: open Schedule, verify one row of four chips; tap Today and All to confirm layout, but do not modify suspected broken-dependency Oct1 test appointment #234.
Required release checks: Flutter analyzer/tests, iOS compile, permanent signer fingerprint and exact package, incremented versionCode, signed artifact.
