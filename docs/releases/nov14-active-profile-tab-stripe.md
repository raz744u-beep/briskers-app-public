# Employee Profile active tab stripe

Continues b4660 (40f9b3ae71ca5f008f55e5784b14ffe2053489f9). Scope: the Owner’s explicit active-tab stripe correction only. Other post-install ZIP touch-ups are not included in this change.

- Active background and full-width bottom stripe use the same existing tab color value. Removed the active darkening gradient.
- Stripe belongs to the selected tab rather than an animated indicator sliding beneath inactive tabs.
- Neutral inactive tabs, clipping shapes, four equal widths, 40px height, labels, icons, spacing and routing retained.
- No payroll, database, assignment, financial, receipt, invoice or sync logic changes.

Verification before build: 6 focused UI/navigation tests passed; analyzer clean. Rendered RGBA pixels match the active color across the entire stripe, including both edges, for all four tabs at 360px and 412px logical widths. Verified stripe removal during tab switching. Actual tab renders inspected.

Release workflow requires a build newer than 4660 and actual same-identity install-over from the verified signed b4660 artifact. Signature, installation evidence and APK will be reported after completion. Owner approval remains pending installed-phone inspection.
