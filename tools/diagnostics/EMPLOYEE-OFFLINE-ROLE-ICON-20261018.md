# QA build request — Employee offline role styling — 2026-10-18

Base: signed Briskers b2314, valid offline roster. Draft PR #231.
Phone screenshot Oct 18 ~1:21 PM shows saved employee names in Force Offline, but all roles incorrectly show "No position" and generic gray badges.
Code fix: offline employee display uses safe cached position_name as fallback for online position; preserves role-specific icons and colors; hide inactive-looking chevrons/Manage FAB and repetitive Offline roster text. No pay, SSN, contact field changes and no business mutation.

Signing/installation: versionCode >2314, same certificate as b2314, com.briskers.briskers_app. Install OVER existing Android without uninstall/clear data.
Phone acceptance: keep Force Offline; Settings→Employees should show original role names/colors/icons (Porter orange, Mechanic blue, Owner navy, Secretary purple), all five names, "Saved employee roster (read-only)" banner, no pay/SSN, no misleading row chevrons/Manage.
No changes to receipts, invoice, tax, payroll, deletion or server DB permitted from build.
