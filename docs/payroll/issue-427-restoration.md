# Tasks and Payroll restoration

The signed b2567 source is `267798b77403d147b4223927e863414931b616e4`.
The last recovered Tasks TEST source is `d92595b26dab21d19927cf9fac56305ab878b48c`.
PR #366 provides a status-policy checkpoint. Its code does not contain the later approved screens.
The recovered branch contains the amount selection, collapsed debt deduction, repayment validation, full-screen history, and flexible-pay refinements.
History sources include `00dd3bdf` for full-screen details, `b4617082` for links, and `ee6cbf4b` for the expansion hint.
Tasks Workspace sources include `8635bdf6` for Service and General Tasks, `1ea516fe` for the responsive filters, and `1bb039aa` for separate status pills.
Flexible payroll sources include `41644787` for the weekly settlement and `fa676b78` for net disbursement accounting.

| Surface | Approved source or contract | b2567 | Restoration status |
| --- | --- | --- | --- |
| Employee Details | Employee profile header and Details action, #427 | Edit form shows blank sensitive fields in Force Offline | Known roster name and position visible. Unavailable private details are explicitly labeled. Recovered profile header and Details action now open from the owner roster. |
| Employee Tasks | Original employee profile, #345 | Mechanic labor screen and invoice action | Recovered Service Tasks and General Tasks controls use employee-scoped records. General tasks persist locally. |
| Global and Job Tasks | Original Tasks workspace, #305 and #345 | Manual invoice action | Job menu opens Tasks and reads invoice labor using its actual invoice IDs. Global workspace, automatic invoice-first creation, and separate rechecks still missing. |
| Weekly Labor Review | Original weekly review, #89, #335, #342 | Basic completed-work checklist | Recovered weekly review, carry-forward selection, fixed footer, and payment confirmation are bound to real completed credits. Partial payment within a single credit and assigned-hours editing still missing. |
| Payroll and Advances | Original employee profile, #341, #343, #399 | Basic totals and verified payment | Recovered summary cards, period filters, optional payment deductions, and standalone repayment form. Recovered opening-balance control and flexible weekly preview with locally saved defaults. Fixed and flexible weekly settlement still missing. |
| Reports and week details | History panel and #371 | Flat payment history | Recovered period filters, weekly cards, full-screen details, frozen paid work and separate scoped Job and Invoice links. |
| Taxes & 1099 | Original employee profile | Employee details form | Recovered Taxes tab and Taxes & 1099 card. The original test kept tax calculations and filing disabled. |
| Owner payment authorization | #427 | One pinned payment phone | Outside the current UI restoration pass. |

## Reconciliation

Issue #372 reports different scopes in Tasks TEST. The restored history groups by the recorded payroll week and uses the verified settlement for gross, debt repaid, and transferred amounts. Frozen task allocations remain visible as work detail and are excluded from the settlement total calculation. The original TEST device ledger was not available to establish what created its historical $105 figure.

## Delivery gates

The current changes are a draft on the b2567 baseline. Remaining gates include UI parity evidence, payroll settlement coordination and offline conflict prevention, real weekly payroll integration, Android and iOS verification, physical shop Wi-Fi tests, and signed install-over verification. No production writes or migrations are part of this draft.
