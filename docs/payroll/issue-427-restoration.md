# Tasks and Payroll restoration

The signed b2567 source is `267798b77403d147b4223927e863414931b616e4`.
The last recovered Tasks TEST source is `d92595b26dab21d19927cf9fac56305ab878b48c`.
PR #366 provides a status-policy checkpoint. Its code does not contain the later approved screens.
The recovered branch contains the amount selection, collapsed debt deduction, repayment validation, full-screen history, and flexible-pay refinements.

| Surface | Approved source or contract | b2567 | Restoration status |
| --- | --- | --- | --- |
| Employee Details | Employee profile header and Details action, #427 | Edit form shows blank sensitive fields in Force Offline | Known roster name and position visible. Unavailable private details are explicitly labeled. Full profile header still missing. |
| Employee Tasks | Original employee profile, #345 | Mechanic labor screen and invoice action | Approved tabs, work cards, and employee task navigation still missing. |
| Global and Job Tasks | Original Tasks workspace, #305 and #345 | Manual invoice action | Jobs and Shop Tasks split, invoice-first creation, separate rechecks, and per-mechanic progress still missing. |
| Weekly Labor Review | Original weekly review, #89, #335, #342 | Basic completed-work checklist | Weekly selection, carry-forward, independent paid status, and original confirmation still missing. |
| Payroll and Advances | Original employee profile, #341, #343, #399 | Basic totals and verified payment | Approved cards, weekly base and optional hours, and repayment forms still missing. |
| Reports and week details | History panel and #371 | Flat payment history | Recovered period filters, weekly cards, full-screen details, frozen paid work and separate scoped Job and Invoice links. |
| Taxes & 1099 | Original employee profile | Employee details form | Approved section still missing. |
| Owner payment authorization | #427 | One pinned payment phone | Cross-platform authenticated settlement authority and a safe offline coordination boundary still missing. |

## Reconciliation

Issue #372 reports different scopes in Tasks TEST. The restored history groups by the recorded payroll week and uses the verified settlement for gross, debt repaid, and transferred amounts. Frozen task allocations remain visible as work detail and are excluded from the settlement total calculation. The original TEST device ledger was not available to establish what created its historical $105 figure.

## Delivery gates

The current changes are a draft on the b2567 baseline. Remaining gates include UI parity evidence, payroll settlement coordination and offline conflict prevention, real weekly payroll integration, Android and iOS verification, physical shop Wi-Fi tests, and signed install-over verification. No production writes or migrations are part of this draft.
