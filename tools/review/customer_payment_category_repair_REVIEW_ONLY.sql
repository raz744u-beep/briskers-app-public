-- REVIEW ONLY: default is ROLLBACK. No live execution authorized.
-- Run the preview first. Approve business UUID, candidate count and manifest
-- fingerprint before setting the three session values below. Do not infer shop.
BEGIN;
DO $review$
BEGIN
  IF nullif(current_setting('briskers.repair_business_id',true),'') IS NULL OR
     nullif(current_setting('briskers.repair_expected_count',true),'') IS NULL OR
     nullif(current_setting('briskers.repair_manifest_md5',true),'') IS NULL THEN
    RAISE EXCEPTION 'Reviewed business, count and manifest fingerprint required';
  END IF;
END;
$review$;
CREATE TEMP TABLE customer_category_repair_manifest ON COMMIT DROP AS
SELECT t.id, t.business_id, t.row_version, to_jsonb(t) AS before_record,
  c.id AS target_category_id,
  (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.id),'[]'::jsonb)
   FROM briskers.payment_allocations a
   WHERE a.business_id=t.business_id AND a.transaction_id=t.id) AS allocations
FROM briskers.financial_transactions t
JOIN briskers.customers customer ON customer.business_id=t.business_id AND customer.id=t.customer_id
JOIN briskers.financial_categories c ON c.business_id=t.business_id
  AND lower(btrim(c.name))='customers' AND c.active
  AND c.normal_direction='income' AND c.report_treatment='revenue'
WHERE t.business_id=nullif(current_setting('briskers.repair_business_id',true),'')::uuid
  AND t.kind='customer_payment' AND t.status='posted' AND t.category_id IS NULL
  AND (SELECT count(*) FROM briskers.financial_categories candidate
    WHERE candidate.business_id=t.business_id AND candidate.active
      AND lower(btrim(candidate.name))='customers'
      AND candidate.normal_direction='income' AND candidate.report_treatment='revenue')=1;
-- Lock candidate rows and category before checking the reviewed manifest.
SELECT t.id FROM briskers.financial_transactions t
JOIN customer_category_repair_manifest m ON m.id=t.id AND m.business_id=t.business_id FOR UPDATE OF t;
DO $review$
DECLARE actual_count integer; actual_md5 text; changed integer;
BEGIN
  SELECT count(*),md5(coalesce(string_agg(id::text||':'||row_version::text||':'||target_category_id::text,',' ORDER BY id),''))
  INTO actual_count,actual_md5 FROM customer_category_repair_manifest;
  IF actual_count<>current_setting('briskers.repair_expected_count')::integer OR
     actual_md5<>current_setting('briskers.repair_manifest_md5') THEN
    RAISE EXCEPTION 'Repair manifest changed; preview and review again';
  END IF;
  UPDATE briskers.financial_transactions t SET category_id=m.target_category_id
  FROM customer_category_repair_manifest m
  WHERE t.business_id=m.business_id AND t.id=m.id AND t.row_version=m.row_version
    AND t.category_id IS NULL AND t.status='posted' AND t.kind='customer_payment';
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed<>actual_count THEN RAISE EXCEPTION 'Concurrent change; entire repair rolled back'; END IF;
  IF EXISTS (SELECT 1 FROM customer_category_repair_manifest m
    JOIN briskers.financial_transactions t ON t.business_id=m.business_id AND t.id=m.id
    WHERE (to_jsonb(t)-ARRAY['category_id','updated_at','row_version']) IS DISTINCT FROM
          (m.before_record-ARRAY['category_id','updated_at','row_version']) OR
      m.allocations IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.id),'[]'::jsonb)
      FROM briskers.payment_allocations a WHERE a.business_id=m.business_id AND a.transaction_id=m.id)) THEN
    RAISE EXCEPTION 'Protected accounting values changed; entire repair rolled back';
  END IF;
END;
$review$;
-- Export this nonfinancial audit (IDs/category/version only) to the approved
-- private audit destination before a separately authorized commit. No new tx.
SELECT id,business_id,row_version,target_category_id FROM customer_category_repair_manifest ORDER BY id;
ROLLBACK;
