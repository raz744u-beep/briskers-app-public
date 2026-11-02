# Briskers b2327 payment-visibility follow-up — phone-test candidate

Owner reports roughly one minute for a newly entered invoice payment to appear
in Expenses & Income. Searching invoice #6342 eventually showed Richard Goff's
paid receipt, indicating a visibility/refresh issue rather than proof of missing
payment. Invoice #6334's linked Expenses amounts also display too small.

Changes on this isolated branch:
- Start receipt inventory refresh before expensive historical transaction download
- Display first receipt page as soon as received, keeping queued payments
- Preserve fresh server receipts when search refresh reads an older local snapshot
- Show first financial page before 1,000-row archive/cache and option hydration
- Keep old visible list during refresh, guard stale list results and receipt paging
- Match invoice linked-expense amount typography to main Expenses (17.5sp, w900)
- Source regression tests for sequencing, search-safe receipts and amount parity

No financial or production database writes, no new payments, no queue clearing.
The issue is NOT accepted until a signed higher-build APK is tested on Samsung
with newly saved cash/card payment, search, offline and background navigation.
Do not merge into old main. Source base: b2327 performance PR #255.

CI: exact-commit Flutter Diagnostics and iOS compile must pass before signed
Android release build. Verify package and permanent Briskers signing certificate.
