-- Read-only preview. The caller must bind the reviewed business UUID using
-- set_config('briskers.repair_business_id', <UUID>, false). No row mutations.
WITH candidates AS (
  SELECT t.id,t.row_version,c.id AS target_category_id
  FROM briskers.financial_transactions t
  JOIN briskers.customers customer ON customer.business_id=t.business_id AND customer.id=t.customer_id
  JOIN briskers.financial_categories c ON c.business_id=t.business_id AND c.active
    AND lower(btrim(c.name))='customers' AND c.normal_direction='income' AND c.report_treatment='revenue'
  WHERE t.business_id=nullif(current_setting('briskers.repair_business_id',true),'')::uuid
    AND t.kind='customer_payment' AND t.status='posted' AND t.category_id IS NULL
    AND (SELECT count(*) FROM briskers.financial_categories candidate
      WHERE candidate.business_id=t.business_id AND candidate.active
        AND lower(btrim(candidate.name))='customers' AND candidate.normal_direction='income'
        AND candidate.report_treatment='revenue')=1
)
SELECT count(*) AS candidate_count,
 md5(coalesce(string_agg(id::text||':'||row_version::text||':'||target_category_id::text,',' ORDER BY id),'')) AS manifest_md5
FROM candidates;
