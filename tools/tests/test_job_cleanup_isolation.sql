-- SYNTHETIC ONLY. Separate request after the cases file, so BEGIN establishes
-- a new snapshot. Requires fixtures, migration and cases from this directory.
-- Ordinary unrelated writes remain compatible with REPEATABLE READ, including
-- INSERT/identity guard UPSERTs. Only cleanup itself requires READ COMMITTED.
BEGIN ISOLATION LEVEL REPEATABLE READ;
UPDATE briskers.jobs SET title='Unrelated repeatable-read edit' WHERE id='40000000-0000-0000-0000-000000000008';
INSERT INTO briskers.jobs(id,business_id,customer_id,job_number,title)
VALUES('40000000-0000-0000-0000-000000000099','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','J-999','Synthetic repeatable-read insert');
ROLLBACK;

SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.jobs WHERE id='40000000-0000-0000-0000-000000000099')=0,'repeatable-read synthetic insert rolled back');
