# Weekly labor and estimate conversion follow-up

Owner evidence from build 4720:

- Chris has only J-56 active this week: 20 assigned, 8 paid, 12 remaining.
- Weekly Labor incorrectly includes another 14.60 completed hours.
- The completed-task list shows Gloria J-40 labor of 3.6 + 10.0 + 1.0 hours,
  confirmed by the Owner as previously paid, and a second 3.6-hour listing.
- Jennifer McCrossen E-2007 displays Draft although the Owner confirms conversion.
  Invoice 6377 is Closed and has the same 1879.03 total. Matching totals are not
  used to establish the conversion identity.

Corrections:

1. Weekly projections exclude archived work from a later week. Historical work
   remains visible in its original known invoice week. Genuine Done work uses
   its saved completion date before scheduling dates; undated paid work does
   not become new weekly activity merely because it has an inherited date.
2. Task aliases require a verified invoice creation alias, equal ordered labor
   position, description, assigned employee set and assigned minutes. They are
   excluded from duplicate listings and new payroll selection. Physical tasks,
   assignments, coverage and payments remain untouched. Ambiguity or different
   assignments/hours prevents automatic suppression.
3. Owner Work has a read-only hours breakdown, including excluded rows, source
   invoice/job/task/allocation/line IDs, dates, hours and payment flags. Copying
   this report needs no connection. It supplies the exact S26 identities needed
   if a listing cannot be conclusively matched by the conservative alias rule.
4. Estimate details, list and customer history share explicit saved conversion
   evidence. An invoice's exact converted_from_estimate_id can restore a lost
   estimate flag; stale estimate snapshots cannot erase a valid saved link.
   A retired conversion remains excluded under the existing retirement rule.
   Read-only legacy estimates are not automatically labelled Converted.
   Conversion replay also updates the visible server estimate, not only its
   former local cache key, and retains the exact reverse source ID on the
   invoice after optional warranty refresh. Legacy cache redirects can recover
   this relationship without matching customer names or totals.

No payroll payment, expense, invoice amount, customer receipt, financial date,
or completed investigation is rewritten by these projections. No production
network access is required. Owner verification on the S26 remains necessary;
the screenshot alone does not expose the internal IDs of the two strut tasks.
