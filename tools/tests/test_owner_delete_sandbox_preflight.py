"""No network, payment, or database access. Synthetic SQL fixtures only."""
import unittest

from owner_delete_sandbox_preflight import check_baseline, REQUIRED_BEFORE_REPLAY


def synthetic_baseline(quoted=False):
    schema = '"briskers"' if quoted else 'briskers'
    return "\n".join(
        [f"CREATE SCHEMA IF NOT EXISTS {schema};"]
        + [f"CREATE TABLE IF NOT EXISTS {schema}.{name} (id uuid PRIMARY KEY);"
           for name in REQUIRED_BEFORE_REPLAY]
    )


class TestSandboxPreflight(unittest.TestCase):
    def test_empty_valid_schema_unquoted(self):
        self.assertEqual(check_baseline(synthetic_baseline()), [])

    def test_empty_valid_schema_quoted(self):
        self.assertEqual(check_baseline(synthetic_baseline(quoted=True)), [])

    def test_empty_migrations_cannot_initialize_first_migration(self):
        errors = check_baseline("CREATE INDEX IF NOT EXISTS idx ON briskers.appointment_requests(id);")
        self.assertTrue(any("CREATE SCHEMA" in x for x in errors))
        self.assertTrue(any("appointment_requests" in x for x in errors))

    def test_missing_first_dependency_rejected(self):
        text = synthetic_baseline().replace(
            "CREATE TABLE IF NOT EXISTS briskers.appointment_requests (id uuid PRIMARY KEY);", ""
        )
        self.assertTrue(any("appointment_requests" in x for x in check_baseline(text)))

    def test_data_copy_rejected(self):
        sql = synthetic_baseline() + "\nCOPY briskers.customers FROM STDIN;"
        self.assertTrue(any("COPY" in x for x in check_baseline(sql)))

    def test_business_data_insert_rejected(self):
        sql = synthetic_baseline() + "\nINSERT INTO briskers.customers VALUES ('real');"
        self.assertTrue(any("customers" in x for x in check_baseline(sql)))

    def test_comments_do_not_fake_schema(self):
        content = "-- CREATE SCHEMA briskers;\n/* CREATE TABLE briskers.jobs(id uuid); */"
        self.assertTrue(any("CREATE SCHEMA" in x for x in check_baseline(content)))

    def test_no_psql_external_include(self):
        sql = synthetic_baseline() + "\n\\i /tmp/unknown.sql"
        self.assertTrue(any("psql" in x for x in check_baseline(sql)))


if __name__ == "__main__":
    unittest.main()
