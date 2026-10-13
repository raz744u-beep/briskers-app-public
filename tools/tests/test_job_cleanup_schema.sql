-- SYNTHETIC ONLY. Run in a new empty disposable PostgreSQL/PGlite database.
-- No production data or credentials. Mirrors verified column/default/FK shape
-- on 2026-10-13; intentionally omits unrelated business triggers and CHECKs.
-- Never run this fixture against an existing database.
CREATE SCHEMA auth;
CREATE SCHEMA briskers;
DO $$ BEGIN CREATE ROLE anon; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
CREATE TABLE briskers.activity_events(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 actor_user_id uuid,
 actor_name text,
 action text NOT NULL,
 entity_type text NOT NULL,
 entity_id uuid,
 job_id uuid,
 customer_id uuid,
 document_number text,
 before_values jsonb,
 after_values jsonb,
 occurred_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.appointment_cancel_operations(
 business_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 appointment_id uuid NOT NULL,
 base_version int8 NOT NULL,
 resulting_version int8,
 created_at timestamptz DEFAULT now()
);
CREATE TABLE briskers.appointment_create_operations(
 business_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 request_payload jsonb NOT NULL,
 appointment_id uuid,
 created_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.appointment_delete_operations(
 business_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 appointment_id uuid NOT NULL,
 base_version int8 NOT NULL,
 completed_at timestamptz,
 created_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.appointment_edit_operations(
 business_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 appointment_id uuid NOT NULL,
 request_payload jsonb NOT NULL,
 resulting_version int8,
 created_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.appointment_reassign_operations(
 business_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 appointment_id uuid NOT NULL,
 request_payload jsonb NOT NULL,
 resulting_version int8,
 created_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.appointment_requests(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 vehicle_id uuid,
 requested_by uuid NOT NULL,
 preferred_start timestamptz NOT NULL,
 preferred_end timestamptz,
 description text NOT NULL,
 status text DEFAULT 'pending'::text NOT NULL,
 proposed_start timestamptz,
 decision_note text,
 decided_by uuid,
 decided_at timestamptz,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.appointments(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid,
 request_id uuid,
 employee_id uuid,
 starts_at timestamptz NOT NULL,
 ends_at timestamptz NOT NULL,
 status text DEFAULT 'confirmed'::text NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 customer_id uuid NOT NULL,
 vehicle_id uuid,
 title text DEFAULT 'Appointment'::text NOT NULL,
 description text
);
CREATE TABLE briskers.attachments(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 original_filename text,
 legacy_photo_id text,
 storage_bucket text DEFAULT 'briskers-private'::text NOT NULL,
 storage_key text NOT NULL,
 mime_type text,
 byte_size int8,
 sha256 text,
 state text DEFAULT 'pending'::text NOT NULL,
 uploaded_by uuid,
 uploaded_at timestamptz,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.authorizations(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid,
 document_id uuid,
 title text NOT NULL,
 text_version text NOT NULL,
 body text NOT NULL,
 signature_required bool DEFAULT false NOT NULL,
 signature_attachment_id uuid,
 signed_pdf_attachment_id uuid,
 signed_at timestamptz,
 signer_name text,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 signed_document_version int8
);
CREATE TABLE briskers.businesses(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 name text NOT NULL,
 business_kind text DEFAULT 'auto_repair'::text NOT NULL,
 timezone text DEFAULT 'America/Chicago'::text NOT NULL,
 currency_code text DEFAULT 'USD'::text NOT NULL,
 week_starts_on int2 DEFAULT 1 NOT NULL,
 phone text,
 email text,
 address jsonb DEFAULT '{}'::jsonb NOT NULL,
 latitude numeric,
 longitude numeric,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 operating_hours text,
 google_reviews_url text,
 facebook_page_url text,
 about_service text,
 sales_tax_rate numeric DEFAULT 0 NOT NULL,
 invoice_warranty_message text,
 warranty_card_surcharge_rate numeric DEFAULT 0.03 NOT NULL
);
CREATE TABLE briskers.catalog_costs(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 item_id uuid NOT NULL,
 default_cost numeric DEFAULT 0 NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.catalog_items(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 description text,
 item_type text DEFAULT 'non_inventory'::text NOT NULL,
 selling_price numeric DEFAULT 0 NOT NULL,
 pricing_unit text,
 taxable bool DEFAULT true NOT NULL,
 tax_code_legacy text,
 category text,
 barcode text,
 on_hand_quantity numeric,
 available_quantity numeric,
 source_picture text,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 cost numeric DEFAULT 0 NOT NULL,
 source_system text,
 source_item_id text
);
CREATE TABLE briskers.conversation_members(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 conversation_id uuid NOT NULL,
 user_id uuid NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.conversations(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid,
 job_id uuid,
 channel text DEFAULT 'customer'::text NOT NULL,
 subject text,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.customer_account_requests(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 email text NOT NULL,
 source text DEFAULT 'kiosk'::text NOT NULL,
 status text DEFAULT 'pending'::text NOT NULL,
 requested_at_device timestamptz,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.customer_contacts(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 kind text NOT NULL,
 label text,
 value text NOT NULL,
 is_primary bool DEFAULT false NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.customer_create_replay(
 business_id uuid NOT NULL,
 operation_id text NOT NULL,
 request_payload jsonb NOT NULL,
 customer_id uuid,
 created_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.customer_note_attachments(
 business_id uuid NOT NULL,
 note_id uuid NOT NULL,
 attachment_id uuid NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.customer_notes(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 body text,
 visible_to_customer bool DEFAULT true NOT NULL,
 seen_at timestamptz,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 note_type text DEFAULT 'general'::text NOT NULL,
 vehicle_id uuid,
 found_job_id uuid,
 resolved_job_id uuid,
 finding_status text,
 resolved_at timestamptz,
 include_on_invoice bool DEFAULT false NOT NULL,
 found_document_id uuid,
 resolved_document_id uuid,
 repair_job_id uuid
);
CREATE TABLE briskers.customer_private(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 drivers_license_raw text,
 license_state text,
 internal_notes text,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.customer_user_links(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 user_id uuid NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.customers(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 display_name text NOT NULL,
 is_company bool DEFAULT false NOT NULL,
 email text,
 phone_raw text,
 billing_address jsonb DEFAULT '{}'::jsonb NOT NULL,
 taxable bool DEFAULT true NOT NULL,
 tax_code_legacy text,
 terms_legacy text,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 problem_flag bool DEFAULT false NOT NULL,
 problem_flag_note text
);
CREATE TABLE briskers.device_tokens(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 user_id uuid NOT NULL,
 platform text NOT NULL,
 token text NOT NULL,
 active bool DEFAULT true NOT NULL,
 last_seen_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.disclaimer_templates(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 body text NOT NULL,
 signature_required bool DEFAULT true NOT NULL,
 active bool DEFAULT true NOT NULL,
 sort_order int4 DEFAULT 100 NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.document_attachments(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 document_id uuid NOT NULL,
 attachment_id uuid NOT NULL,
 document_version int8 NOT NULL,
 is_current bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.document_counters(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 document_kind text NOT NULL,
 prefix text DEFAULT ''::text NOT NULL,
 next_number int8 NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.document_disclaimers(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 document_id uuid NOT NULL,
 template_id uuid,
 title text NOT NULL,
 body text NOT NULL,
 signature_required bool DEFAULT true NOT NULL,
 authorization_id uuid,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.document_note_templates(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 body text NOT NULL,
 template_type text DEFAULT 'standard'::text NOT NULL,
 show_in_quick_list bool DEFAULT true NOT NULL,
 active bool DEFAULT true NOT NULL,
 sort_order int4 DEFAULT 100 NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.document_number_reuse(
 business_id uuid NOT NULL,
 document_kind text NOT NULL,
 number_value int8 NOT NULL,
 prefix text DEFAULT ''::text NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.document_reassignment_restore(
 business_id uuid NOT NULL,
 document_id uuid NOT NULL,
 prior_job_id uuid,
 prior_source_estimate_id uuid,
 prior_customer_id uuid NOT NULL,
 prior_vehicle_id uuid,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.document_revisions(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 document_id uuid NOT NULL,
 reason text,
 snapshot jsonb NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.employee_compensation(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 employee_id uuid NOT NULL,
 effective_from date DEFAULT CURRENT_DATE NOT NULL,
 payment_type text NOT NULL,
 hourly_rate numeric,
 weekly_rate numeric,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.employee_positions(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 active bool DEFAULT true NOT NULL,
 sort_order int4 DEFAULT 0 NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.employee_private(
 business_id uuid NOT NULL,
 employee_id uuid NOT NULL,
 ssn_cipher bytea,
 ssn_last4 text,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL
);
CREATE TABLE briskers.employee_rates(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 employee_id uuid NOT NULL,
 effective_from date NOT NULL,
 hourly_rate numeric NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.employees(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 display_name text NOT NULL,
 user_id uuid,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 phone text,
 email text,
 address text,
 position_id uuid,
 payment_type text,
 compensation_enabled bool DEFAULT true NOT NULL
);
CREATE TABLE briskers.expense_allocations(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 transaction_id uuid NOT NULL,
 category_id uuid NOT NULL,
 job_id uuid,
 amount numeric NOT NULL,
 memo text,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 document_id uuid
);
CREATE TABLE briskers.expense_attachments(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 transaction_id uuid NOT NULL,
 attachment_id uuid NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.expense_receipt_details(
 business_id uuid NOT NULL,
 transaction_id uuid NOT NULL,
 vendor_invoice_number text,
 receipt_date date,
 receipt_total numeric,
 item_summary text,
 extraction_source text DEFAULT 'manual'::text NOT NULL,
 raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.expense_receipt_items(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 transaction_id uuid NOT NULL,
 position int4 NOT NULL,
 description text NOT NULL,
 sku text,
 quantity numeric,
 unit_price numeric,
 total_amount numeric,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.expenseiq_photo_map(
 business_id uuid NOT NULL,
 source_record_key text NOT NULL,
 photo_id text NOT NULL,
 source_title text,
 source_remarks text,
 source_tran_date int8,
 updated_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.financial_accounts(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 account_kind text NOT NULL,
 currency_code text DEFAULT 'USD'::text NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 is_default_expense bool DEFAULT false NOT NULL
);
CREATE TABLE briskers.financial_categories(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 parent_id uuid,
 name text NOT NULL,
 report_treatment text DEFAULT 'review'::text NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 normal_direction text DEFAULT 'expense'::text NOT NULL
);
CREATE TABLE briskers.financial_transactions(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 account_id uuid NOT NULL,
 kind text NOT NULL,
 amount numeric NOT NULL,
 currency_code text DEFAULT 'USD'::text NOT NULL,
 transaction_date date NOT NULL,
 status text DEFAULT 'posted'::text NOT NULL,
 legacy_status text,
 category_id uuid,
 vendor_id uuid,
 customer_id uuid,
 payment_method_id uuid,
 payee_text text,
 remarks text,
 external_reference text,
 idempotency_key uuid NOT NULL,
 transfer_group_id uuid,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 recurring_rule_id uuid,
 recurring_occurrence_date date
);
CREATE TABLE briskers.import_batches(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 source_system text NOT NULL,
 source_filename text NOT NULL,
 source_sha256 text NOT NULL,
 status text DEFAULT 'staged'::text NOT NULL,
 row_count int8,
 account_allowlist jsonb DEFAULT '[]'::jsonb NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.import_issues(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 batch_id uuid NOT NULL,
 source_row_number int8,
 issue_code text NOT NULL,
 severity text NOT NULL,
 details jsonb NOT NULL,
 resolved bool DEFAULT false NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.import_rows(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 batch_id uuid NOT NULL,
 source_entity text NOT NULL,
 source_row_number int8 NOT NULL,
 source_record_key text,
 raw_data jsonb NOT NULL,
 status text DEFAULT 'pending'::text NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.invoice_payment_operation_keys(
 business_id uuid NOT NULL,
 operation_id uuid NOT NULL,
 invoice_id uuid NOT NULL,
 method_id uuid NOT NULL,
 amount numeric NOT NULL,
 pending_payment_id uuid,
 created_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.invoice_pending_payments(
 invoice_id uuid NOT NULL,
 business_id uuid NOT NULL,
 amount numeric NOT NULL,
 payment_method_id uuid,
 account_id uuid,
 entered_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 entered_by uuid,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 id uuid DEFAULT gen_random_uuid() NOT NULL
);
CREATE TABLE briskers.invoice_status_styles(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 code text NOT NULL,
 name text NOT NULL,
 color_hex text NOT NULL,
 icon_key text NOT NULL,
 sort_order int4 DEFAULT 0 NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.item_categories(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 sort_order int4 DEFAULT 0 NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.job_assignment_requests(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 employee_id uuid NOT NULL,
 status text DEFAULT 'pending'::text NOT NULL,
 requested_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 responded_at timestamptz,
 responded_by uuid,
 note text,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.job_assignments(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 employee_id uuid NOT NULL,
 planned_paid_hours numeric DEFAULT 0 NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.job_attachments(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 attachment_id uuid NOT NULL,
 caption text,
 shared_with_customer bool DEFAULT false NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.job_internal_notes(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 body text NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.job_labor(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 assignment_id uuid NOT NULL,
 paid_hours numeric NOT NULL,
 hourly_rate numeric NOT NULL,
 amount numeric GENERATED ALWAYS AS (round((paid_hours * hourly_rate), 2)) STORED,
 status text DEFAULT 'planned'::text NOT NULL,
 earned_on date,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.job_pre_inspection_photos(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 inspection_id uuid NOT NULL,
 attachment_id uuid NOT NULL,
 note text,
 captured_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_by uuid,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 deleted_at timestamptz
);
CREATE TABLE briskers.job_pre_inspections(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 vehicle_id uuid,
 inspected_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 odometer numeric,
 notes text,
 created_by uuid,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL
);
CREATE TABLE briskers.job_status_events(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 from_status text,
 to_status text NOT NULL,
 note text,
 changed_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 changed_by uuid
);
CREATE TABLE briskers.job_statuses(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 code text NOT NULL,
 name text NOT NULL,
 color_hex text NOT NULL,
 icon_key text NOT NULL,
 active bool DEFAULT true NOT NULL,
 sort_order int4 DEFAULT 0 NOT NULL,
 is_system bool DEFAULT false NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.job_visit_assignments(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 visit_id uuid NOT NULL,
 employee_id uuid NOT NULL,
 source text DEFAULT 'office'::text NOT NULL,
 request_id uuid,
 assigned_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 released_at timestamptz,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.job_visits(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 visit_number int4 NOT NULL,
 reason text,
 planned_hours numeric DEFAULT 0 NOT NULL,
 work_summary text,
 opened_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 closed_at timestamptz,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.jobs(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 vehicle_id uuid,
 job_number text NOT NULL,
 title text NOT NULL,
 requested_work text,
 status text DEFAULT 'open'::text NOT NULL,
 odometer_in numeric,
 completed_at timestamptz,
 authorization_number text,
 claim_number text,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 planned_hours numeric DEFAULT 0 NOT NULL
);
CREATE TABLE briskers.kiosk_disclaimers(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 version int4 NOT NULL,
 disclaimer_text text NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.kiosk_registrations(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 operation_id text NOT NULL,
 customer_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 job_id uuid NOT NULL,
 disclaimer_id uuid NOT NULL,
 disclaimer_version int4 NOT NULL,
 disclaimer_text_snapshot text NOT NULL,
 accepted_at_device timestamptz NOT NULL,
 received_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 create_online_account_requested bool DEFAULT false NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.legacy_import_stage(
 business_id uuid NOT NULL,
 batch_tag text NOT NULL,
 source_system text NOT NULL,
 record_type text NOT NULL,
 source_key text NOT NULL,
 payload jsonb NOT NULL,
 staged_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.legacy_links(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 source_system text NOT NULL,
 source_entity text NOT NULL,
 source_key text NOT NULL,
 target_entity text NOT NULL,
 target_id uuid NOT NULL,
 batch_id uuid,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.memberships(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 user_id uuid NOT NULL,
 display_name text NOT NULL,
 role_code text NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.message_attachments(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 message_id uuid NOT NULL,
 attachment_id uuid NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.messages(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 conversation_id uuid NOT NULL,
 sender_id uuid NOT NULL,
 body text NOT NULL,
 client_message_id uuid NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.notification_outbox(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 recipient_user_id uuid NOT NULL,
 event_key text NOT NULL,
 event_kind text NOT NULL,
 payload jsonb DEFAULT '{}'::jsonb NOT NULL,
 status text DEFAULT 'pending'::text NOT NULL,
 attempts int4 DEFAULT 0 NOT NULL,
 next_attempt_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 sent_at timestamptz,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.payment_allocations(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 transaction_id uuid NOT NULL,
 document_id uuid NOT NULL,
 gross_amount numeric NOT NULL,
 tax_amount numeric NOT NULL,
 net_amount numeric GENERATED ALWAYS AS ((gross_amount - tax_amount)) STORED,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.payment_methods(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 default_account_id uuid,
 sort_order int4 DEFAULT 0 NOT NULL
);
CREATE TABLE briskers.payroll_allocations(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 transaction_id uuid NOT NULL,
 labor_id uuid NOT NULL,
 amount numeric NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.permission_overrides(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 user_id uuid NOT NULL,
 permission_code text NOT NULL,
 allowed bool NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.permissions(
 code text NOT NULL,
 description text NOT NULL
);
CREATE TABLE briskers.quick_transaction_templates(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 direction text NOT NULL,
 vendor_id uuid,
 account_id uuid NOT NULL,
 category_id uuid NOT NULL,
 remarks text,
 sort_order int4 DEFAULT 0 NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.recurring_occurrences(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 rule_id uuid NOT NULL,
 due_date date NOT NULL,
 transaction_id uuid,
 status text DEFAULT 'pending'::text NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.recurring_rules(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 account_id uuid NOT NULL,
 category_id uuid NOT NULL,
 vendor_id uuid,
 name text NOT NULL,
 frequency text NOT NULL,
 interval_count int4 DEFAULT 1 NOT NULL,
 next_due_date date NOT NULL,
 end_date date,
 fixed_amount numeric,
 auto_post bool DEFAULT false NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.recurring_transactions(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 source_transaction_id uuid,
 direction text NOT NULL,
 vendor_id uuid,
 account_id uuid NOT NULL,
 category_id uuid NOT NULL,
 amount numeric NOT NULL,
 remarks text,
 frequency text NOT NULL,
 interval_count int4 DEFAULT 1 NOT NULL,
 next_date date NOT NULL,
 end_date date,
 is_repeating bool DEFAULT true NOT NULL,
 paused_reason text,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.role_permissions(
 role_code text NOT NULL,
 permission_code text NOT NULL
);
CREATE TABLE briskers.sales_document_estimate_links(
 business_id uuid NOT NULL,
 estimate_id uuid NOT NULL,
 invoice_id uuid NOT NULL,
 operation_id text NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.sales_document_lines(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 document_id uuid NOT NULL,
 position int4 NOT NULL,
 item_id uuid,
 line_kind text DEFAULT 'item'::text NOT NULL,
 name text NOT NULL,
 description text,
 quantity numeric DEFAULT 1 NOT NULL,
 unit_price numeric DEFAULT 0 NOT NULL,
 pricing_unit text,
 tax_rate numeric DEFAULT 0 NOT NULL,
 net_amount numeric DEFAULT 0 NOT NULL,
 tax_amount numeric DEFAULT 0 NOT NULL,
 gross_amount numeric GENERATED ALWAYS AS ((net_amount + tax_amount)) STORED,
 source_row_number int8,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 discount_method text,
 discount_timing text,
 discount_value numeric,
 part_number text,
 imported_unit_price numeric,
 price_verification_status text DEFAULT 'not_applicable'::text NOT NULL,
 dealer_list_price numeric,
 price_source_name text,
 price_source_url text,
 price_checked_at timestamptz,
 price_verification_note text,
 price_verification_confidence text
);
CREATE TABLE briskers.sales_documents(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 kind text NOT NULL,
 customer_id uuid NOT NULL,
 job_id uuid,
 source_estimate_id uuid,
 credited_invoice_id uuid,
 document_number text,
 origin text DEFAULT 'native'::text NOT NULL,
 status text DEFAULT 'draft'::text NOT NULL,
 legacy_status text,
 document_date date,
 source_datetime_raw text,
 due_date date,
 currency_code text DEFAULT 'USD'::text NOT NULL,
 net_amount numeric DEFAULT 0 NOT NULL,
 tax_amount numeric DEFAULT 0 NOT NULL,
 total_amount numeric GENERATED ALWAYS AS ((net_amount + tax_amount)) STORED,
 legacy_discount numeric,
 legacy_shipping numeric,
 customer_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
 vehicle_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
 memo text,
 authorization_number text,
 claim_number text,
 signature_required bool DEFAULT false NOT NULL,
 published_at timestamptz,
 issued_at timestamptz,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 vehicle_id uuid,
 source_system text,
 source_reference text,
 source_imported_at timestamptz,
 source_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
 extended_warranty bool DEFAULT false NOT NULL,
 warranty_company_id uuid,
 warranty_approved_amount numeric,
 warranty_surcharge_rate numeric DEFAULT 0.03 NOT NULL,
 warranty_terminal_amount numeric,
 warranty_processor_fee numeric,
 warranty_net_applied numeric,
 closed_at timestamptz,
 closed_by uuid
);
CREATE TABLE briskers.sales_line_receipt_links(
 business_id uuid NOT NULL,
 sales_document_line_id uuid NOT NULL,
 receipt_item_id uuid NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.sync_applied_operations(
 business_id uuid NOT NULL,
 operation_id text NOT NULL,
 entity_type text NOT NULL,
 result jsonb NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.sync_appointment_changes(
 cursor int8 GENERATED BY DEFAULT AS IDENTITY NOT NULL,
 business_id uuid NOT NULL,
 appointment_id uuid NOT NULL,
 reason text DEFAULT 'change'::text NOT NULL,
 changed_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.sync_customer_changes(
 cursor int8 GENERATED BY DEFAULT AS IDENTITY NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 reason text DEFAULT 'change'::text NOT NULL,
 changed_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.sync_job_changes(
 cursor int8 GENERATED BY DEFAULT AS IDENTITY NOT NULL,
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 reason text DEFAULT 'change'::text NOT NULL,
 changed_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.sync_office_changes(
 cursor int8 GENERATED BY DEFAULT AS IDENTITY NOT NULL,
 business_id uuid NOT NULL,
 customer_id uuid,
 vehicle_id uuid,
 reason text DEFAULT 'change'::text NOT NULL,
 changed_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.vehicle_create_replay(
 business_id uuid NOT NULL,
 operation_id text NOT NULL,
 local_vehicle_id text NOT NULL,
 request_payload jsonb NOT NULL,
 vehicle_id uuid,
 created_at timestamptz DEFAULT now() NOT NULL
);
CREATE TABLE briskers.vehicle_customers(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 valid_from date,
 valid_until date,
 is_primary bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.vehicle_private(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 key_password_raw text,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
CREATE TABLE briskers.vehicles(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 year int4,
 year_raw text,
 make text,
 model text,
 vin_raw text,
 vin_normalized text,
 license_plate text,
 color text,
 odometer numeric,
 odometer_raw text,
 odometer_unit text DEFAULT 'mi'::text NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 license_state text
);
CREATE TABLE briskers.vendor_receipt_training_samples(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 vendor_id uuid NOT NULL,
 attachment_id uuid NOT NULL,
 created_by uuid,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL
);
CREATE TABLE briskers.vendors(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 email text,
 phone text,
 address jsonb DEFAULT '{}'::jsonb NOT NULL,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid,
 default_category_id uuid,
 default_surcharge_percent numeric DEFAULT 0 NOT NULL
);
CREATE TABLE briskers.warranty_companies(
 id uuid DEFAULT gen_random_uuid() NOT NULL,
 business_id uuid NOT NULL,
 name text NOT NULL,
 claims_phone text,
 submission_email text,
 portal_url text,
 notes text,
 active bool DEFAULT true NOT NULL,
 created_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 updated_at timestamptz DEFAULT clock_timestamp() NOT NULL,
 row_version int8 DEFAULT 1 NOT NULL,
 created_by uuid
);
ALTER TABLE briskers.activity_events ADD CONSTRAINT activity_events_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.activity_events ADD CONSTRAINT activity_events_pkey PRIMARY KEY (id);
ALTER TABLE briskers.appointment_cancel_operations ADD CONSTRAINT appointment_cancel_operations_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.appointment_create_operations ADD CONSTRAINT appointment_create_operations_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.appointment_delete_operations ADD CONSTRAINT appointment_delete_operations_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.appointment_edit_operations ADD CONSTRAINT appointment_edit_operations_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.appointment_reassign_operations ADD CONSTRAINT appointment_reassign_operations_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.appointment_requests ADD CONSTRAINT appointment_requests_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.appointment_requests ADD CONSTRAINT appointment_requests_pkey PRIMARY KEY (id);
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_business_id_request_id_key UNIQUE (business_id, request_id);
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.attachments ADD CONSTRAINT attachments_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.attachments ADD CONSTRAINT attachments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.attachments ADD CONSTRAINT attachments_storage_bucket_storage_key_key UNIQUE (storage_bucket, storage_key);
ALTER TABLE briskers.authorizations ADD CONSTRAINT authorizations_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.authorizations ADD CONSTRAINT authorizations_pkey PRIMARY KEY (id);
ALTER TABLE briskers.businesses ADD CONSTRAINT businesses_pkey PRIMARY KEY (id);
ALTER TABLE briskers.catalog_costs ADD CONSTRAINT catalog_costs_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.catalog_costs ADD CONSTRAINT catalog_costs_business_id_item_id_key UNIQUE (business_id, item_id);
ALTER TABLE briskers.catalog_costs ADD CONSTRAINT catalog_costs_pkey PRIMARY KEY (id);
ALTER TABLE briskers.catalog_items ADD CONSTRAINT catalog_items_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.catalog_items ADD CONSTRAINT catalog_items_pkey PRIMARY KEY (id);
ALTER TABLE briskers.conversation_members ADD CONSTRAINT conversation_members_business_id_conversation_id_user_id_key UNIQUE (business_id, conversation_id, user_id);
ALTER TABLE briskers.conversation_members ADD CONSTRAINT conversation_members_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.conversation_members ADD CONSTRAINT conversation_members_pkey PRIMARY KEY (id);
ALTER TABLE briskers.conversations ADD CONSTRAINT conversations_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.conversations ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);
ALTER TABLE briskers.customer_account_requests ADD CONSTRAINT customer_account_requests_pkey PRIMARY KEY (id);
ALTER TABLE briskers.customer_contacts ADD CONSTRAINT customer_contacts_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.customer_contacts ADD CONSTRAINT customer_contacts_pkey PRIMARY KEY (id);
ALTER TABLE briskers.customer_create_replay ADD CONSTRAINT customer_create_replay_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.customer_note_attachments ADD CONSTRAINT customer_note_attachments_pkey PRIMARY KEY (business_id, note_id, attachment_id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_pkey PRIMARY KEY (id);
ALTER TABLE briskers.customer_private ADD CONSTRAINT customer_private_business_id_customer_id_key UNIQUE (business_id, customer_id);
ALTER TABLE briskers.customer_private ADD CONSTRAINT customer_private_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.customer_private ADD CONSTRAINT customer_private_pkey PRIMARY KEY (id);
ALTER TABLE briskers.customer_user_links ADD CONSTRAINT customer_user_links_business_id_customer_id_user_id_key UNIQUE (business_id, customer_id, user_id);
ALTER TABLE briskers.customer_user_links ADD CONSTRAINT customer_user_links_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.customer_user_links ADD CONSTRAINT customer_user_links_pkey PRIMARY KEY (id);
ALTER TABLE briskers.customers ADD CONSTRAINT customers_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.customers ADD CONSTRAINT customers_pkey PRIMARY KEY (id);
ALTER TABLE briskers.device_tokens ADD CONSTRAINT device_tokens_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.device_tokens ADD CONSTRAINT device_tokens_business_id_user_id_token_key UNIQUE (business_id, user_id, token);
ALTER TABLE briskers.device_tokens ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (id);
ALTER TABLE briskers.disclaimer_templates ADD CONSTRAINT disclaimer_templates_business_id_name_key UNIQUE (business_id, name);
ALTER TABLE briskers.disclaimer_templates ADD CONSTRAINT disclaimer_templates_pkey PRIMARY KEY (id);
ALTER TABLE briskers.document_attachments ADD CONSTRAINT document_attachments_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.document_attachments ADD CONSTRAINT document_attachments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.document_counters ADD CONSTRAINT document_counters_business_id_document_kind_key UNIQUE (business_id, document_kind);
ALTER TABLE briskers.document_counters ADD CONSTRAINT document_counters_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.document_counters ADD CONSTRAINT document_counters_pkey PRIMARY KEY (id);
ALTER TABLE briskers.document_disclaimers ADD CONSTRAINT document_disclaimers_pkey PRIMARY KEY (id);
ALTER TABLE briskers.document_note_templates ADD CONSTRAINT document_note_templates_business_id_name_key UNIQUE (business_id, name);
ALTER TABLE briskers.document_note_templates ADD CONSTRAINT document_note_templates_pkey PRIMARY KEY (id);
ALTER TABLE briskers.document_number_reuse ADD CONSTRAINT document_number_reuse_pkey PRIMARY KEY (business_id, document_kind, number_value);
ALTER TABLE briskers.document_reassignment_restore ADD CONSTRAINT document_reassignment_restore_pkey PRIMARY KEY (business_id, document_id);
ALTER TABLE briskers.document_revisions ADD CONSTRAINT document_revisions_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.document_revisions ADD CONSTRAINT document_revisions_pkey PRIMARY KEY (id);
ALTER TABLE briskers.employee_compensation ADD CONSTRAINT employee_compensation_business_id_employee_id_effective_fro_key UNIQUE (business_id, employee_id, effective_from);
ALTER TABLE briskers.employee_compensation ADD CONSTRAINT employee_compensation_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.employee_compensation ADD CONSTRAINT employee_compensation_pkey PRIMARY KEY (id);
ALTER TABLE briskers.employee_positions ADD CONSTRAINT employee_positions_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.employee_positions ADD CONSTRAINT employee_positions_pkey PRIMARY KEY (id);
ALTER TABLE briskers.employee_private ADD CONSTRAINT employee_private_pkey PRIMARY KEY (business_id, employee_id);
ALTER TABLE briskers.employee_rates ADD CONSTRAINT employee_rates_business_id_employee_id_effective_from_key UNIQUE (business_id, employee_id, effective_from);
ALTER TABLE briskers.employee_rates ADD CONSTRAINT employee_rates_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.employee_rates ADD CONSTRAINT employee_rates_pkey PRIMARY KEY (id);
ALTER TABLE briskers.employees ADD CONSTRAINT employees_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.employees ADD CONSTRAINT employees_business_id_user_id_key UNIQUE (business_id, user_id);
ALTER TABLE briskers.employees ADD CONSTRAINT employees_pkey PRIMARY KEY (id);
ALTER TABLE briskers.expense_allocations ADD CONSTRAINT expense_allocations_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.expense_allocations ADD CONSTRAINT expense_allocations_pkey PRIMARY KEY (id);
ALTER TABLE briskers.expense_attachments ADD CONSTRAINT expense_attachments_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.expense_attachments ADD CONSTRAINT expense_attachments_business_id_transaction_id_attachment_i_key UNIQUE (business_id, transaction_id, attachment_id);
ALTER TABLE briskers.expense_attachments ADD CONSTRAINT expense_attachments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.expense_receipt_details ADD CONSTRAINT expense_receipt_details_pkey PRIMARY KEY (business_id, transaction_id);
ALTER TABLE briskers.expense_receipt_items ADD CONSTRAINT expense_receipt_items_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.expense_receipt_items ADD CONSTRAINT expense_receipt_items_business_id_transaction_id_position_key UNIQUE (business_id, transaction_id, "position");
ALTER TABLE briskers.expense_receipt_items ADD CONSTRAINT expense_receipt_items_pkey PRIMARY KEY (id);
ALTER TABLE briskers.expenseiq_photo_map ADD CONSTRAINT expenseiq_photo_map_pkey PRIMARY KEY (business_id, source_record_key);
ALTER TABLE briskers.financial_accounts ADD CONSTRAINT financial_accounts_business_id_id_currency_code_key UNIQUE (business_id, id, currency_code);
ALTER TABLE briskers.financial_accounts ADD CONSTRAINT financial_accounts_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.financial_accounts ADD CONSTRAINT financial_accounts_pkey PRIMARY KEY (id);
ALTER TABLE briskers.financial_categories ADD CONSTRAINT financial_categories_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.financial_categories ADD CONSTRAINT financial_categories_pkey PRIMARY KEY (id);
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_business_id_idempotency_key_key UNIQUE (business_id, idempotency_key);
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_pkey PRIMARY KEY (id);
ALTER TABLE briskers.import_batches ADD CONSTRAINT import_batches_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.import_batches ADD CONSTRAINT import_batches_business_id_source_system_source_sha256_key UNIQUE (business_id, source_system, source_sha256);
ALTER TABLE briskers.import_batches ADD CONSTRAINT import_batches_pkey PRIMARY KEY (id);
ALTER TABLE briskers.import_issues ADD CONSTRAINT import_issues_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.import_issues ADD CONSTRAINT import_issues_pkey PRIMARY KEY (id);
ALTER TABLE briskers.import_rows ADD CONSTRAINT import_rows_business_id_batch_id_source_row_number_key UNIQUE (business_id, batch_id, source_row_number);
ALTER TABLE briskers.import_rows ADD CONSTRAINT import_rows_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.import_rows ADD CONSTRAINT import_rows_pkey PRIMARY KEY (id);
ALTER TABLE briskers.invoice_payment_operation_keys ADD CONSTRAINT invoice_payment_operation_keys_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.invoice_pending_payments ADD CONSTRAINT invoice_pending_payments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.invoice_status_styles ADD CONSTRAINT invoice_status_styles_business_id_code_key UNIQUE (business_id, code);
ALTER TABLE briskers.invoice_status_styles ADD CONSTRAINT invoice_status_styles_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.invoice_status_styles ADD CONSTRAINT invoice_status_styles_pkey PRIMARY KEY (id);
ALTER TABLE briskers.item_categories ADD CONSTRAINT item_categories_business_id_name_key UNIQUE (business_id, name);
ALTER TABLE briskers.item_categories ADD CONSTRAINT item_categories_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_assignment_requests ADD CONSTRAINT job_assignment_requests_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_assignment_requests ADD CONSTRAINT job_assignment_requests_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_assignments ADD CONSTRAINT job_assignments_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_assignments ADD CONSTRAINT job_assignments_business_id_job_id_employee_id_key UNIQUE (business_id, job_id, employee_id);
ALTER TABLE briskers.job_assignments ADD CONSTRAINT job_assignments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_attachments ADD CONSTRAINT job_attachments_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_attachments ADD CONSTRAINT job_attachments_business_id_job_id_attachment_id_key UNIQUE (business_id, job_id, attachment_id);
ALTER TABLE briskers.job_attachments ADD CONSTRAINT job_attachments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_internal_notes ADD CONSTRAINT job_internal_notes_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_internal_notes ADD CONSTRAINT job_internal_notes_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_labor ADD CONSTRAINT job_labor_business_id_assignment_id_key UNIQUE (business_id, assignment_id);
ALTER TABLE briskers.job_labor ADD CONSTRAINT job_labor_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_labor ADD CONSTRAINT job_labor_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_pre_inspection_photos ADD CONSTRAINT job_pre_inspection_photos_business_id_attachment_id_key UNIQUE (business_id, attachment_id);
ALTER TABLE briskers.job_pre_inspection_photos ADD CONSTRAINT job_pre_inspection_photos_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_pre_inspection_photos ADD CONSTRAINT job_pre_inspection_photos_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_pre_inspections ADD CONSTRAINT job_pre_inspections_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_pre_inspections ADD CONSTRAINT job_pre_inspections_business_id_job_id_key UNIQUE (business_id, job_id);
ALTER TABLE briskers.job_pre_inspections ADD CONSTRAINT job_pre_inspections_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_status_events ADD CONSTRAINT job_status_events_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_status_events ADD CONSTRAINT job_status_events_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_statuses ADD CONSTRAINT job_statuses_business_id_code_key UNIQUE (business_id, code);
ALTER TABLE briskers.job_statuses ADD CONSTRAINT job_statuses_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_visit_assignments ADD CONSTRAINT job_visit_assignments_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_visit_assignments ADD CONSTRAINT job_visit_assignments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.job_visits ADD CONSTRAINT job_visits_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.job_visits ADD CONSTRAINT job_visits_business_id_job_id_visit_number_key UNIQUE (business_id, job_id, visit_number);
ALTER TABLE briskers.job_visits ADD CONSTRAINT job_visits_pkey PRIMARY KEY (id);
ALTER TABLE briskers.jobs ADD CONSTRAINT jobs_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.jobs ADD CONSTRAINT jobs_business_id_job_number_key UNIQUE (business_id, job_number);
ALTER TABLE briskers.jobs ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);
ALTER TABLE briskers.kiosk_disclaimers ADD CONSTRAINT kiosk_disclaimers_business_id_version_key UNIQUE (business_id, version);
ALTER TABLE briskers.kiosk_disclaimers ADD CONSTRAINT kiosk_disclaimers_pkey PRIMARY KEY (id);
ALTER TABLE briskers.kiosk_registrations ADD CONSTRAINT kiosk_registrations_business_id_operation_id_key UNIQUE (business_id, operation_id);
ALTER TABLE briskers.kiosk_registrations ADD CONSTRAINT kiosk_registrations_pkey PRIMARY KEY (id);
ALTER TABLE briskers.legacy_import_stage ADD CONSTRAINT legacy_import_stage_pkey PRIMARY KEY (business_id, batch_tag, source_system, record_type, source_key);
ALTER TABLE briskers.legacy_links ADD CONSTRAINT legacy_links_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.legacy_links ADD CONSTRAINT legacy_links_business_id_source_system_source_entity_source_key UNIQUE (business_id, source_system, source_entity, source_key);
ALTER TABLE briskers.legacy_links ADD CONSTRAINT legacy_links_pkey PRIMARY KEY (id);
ALTER TABLE briskers.memberships ADD CONSTRAINT memberships_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.memberships ADD CONSTRAINT memberships_business_id_user_id_key UNIQUE (business_id, user_id);
ALTER TABLE briskers.memberships ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);
ALTER TABLE briskers.message_attachments ADD CONSTRAINT message_attachments_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.message_attachments ADD CONSTRAINT message_attachments_business_id_message_id_attachment_id_key UNIQUE (business_id, message_id, attachment_id);
ALTER TABLE briskers.message_attachments ADD CONSTRAINT message_attachments_pkey PRIMARY KEY (id);
ALTER TABLE briskers.messages ADD CONSTRAINT messages_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.messages ADD CONSTRAINT messages_business_id_sender_id_client_message_id_key UNIQUE (business_id, sender_id, client_message_id);
ALTER TABLE briskers.messages ADD CONSTRAINT messages_pkey PRIMARY KEY (id);
ALTER TABLE briskers.notification_outbox ADD CONSTRAINT notification_outbox_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.notification_outbox ADD CONSTRAINT notification_outbox_business_id_recipient_user_id_event_key_key UNIQUE (business_id, recipient_user_id, event_key);
ALTER TABLE briskers.notification_outbox ADD CONSTRAINT notification_outbox_pkey PRIMARY KEY (id);
ALTER TABLE briskers.payment_allocations ADD CONSTRAINT payment_allocations_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.payment_allocations ADD CONSTRAINT payment_allocations_business_id_transaction_id_document_id_key UNIQUE (business_id, transaction_id, document_id);
ALTER TABLE briskers.payment_allocations ADD CONSTRAINT payment_allocations_pkey PRIMARY KEY (id);
ALTER TABLE briskers.payment_methods ADD CONSTRAINT payment_methods_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.payment_methods ADD CONSTRAINT payment_methods_business_id_name_key UNIQUE (business_id, name);
ALTER TABLE briskers.payment_methods ADD CONSTRAINT payment_methods_pkey PRIMARY KEY (id);
ALTER TABLE briskers.payroll_allocations ADD CONSTRAINT payroll_allocations_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.payroll_allocations ADD CONSTRAINT payroll_allocations_pkey PRIMARY KEY (id);
ALTER TABLE briskers.permission_overrides ADD CONSTRAINT permission_overrides_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.permission_overrides ADD CONSTRAINT permission_overrides_business_id_user_id_permission_code_key UNIQUE (business_id, user_id, permission_code);
ALTER TABLE briskers.permission_overrides ADD CONSTRAINT permission_overrides_pkey PRIMARY KEY (id);
ALTER TABLE briskers.permissions ADD CONSTRAINT permissions_pkey PRIMARY KEY (code);
ALTER TABLE briskers.quick_transaction_templates ADD CONSTRAINT quick_transaction_templates_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.quick_transaction_templates ADD CONSTRAINT quick_transaction_templates_pkey PRIMARY KEY (id);
ALTER TABLE briskers.recurring_occurrences ADD CONSTRAINT recurring_occurrences_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.recurring_occurrences ADD CONSTRAINT recurring_occurrences_business_id_rule_id_due_date_key UNIQUE (business_id, rule_id, due_date);
ALTER TABLE briskers.recurring_occurrences ADD CONSTRAINT recurring_occurrences_pkey PRIMARY KEY (id);
ALTER TABLE briskers.recurring_rules ADD CONSTRAINT recurring_rules_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.recurring_rules ADD CONSTRAINT recurring_rules_pkey PRIMARY KEY (id);
ALTER TABLE briskers.recurring_transactions ADD CONSTRAINT recurring_transactions_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.recurring_transactions ADD CONSTRAINT recurring_transactions_business_id_source_transaction_id_key UNIQUE (business_id, source_transaction_id);
ALTER TABLE briskers.recurring_transactions ADD CONSTRAINT recurring_transactions_pkey PRIMARY KEY (id);
ALTER TABLE briskers.role_permissions ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_code, permission_code);
ALTER TABLE briskers.sales_document_estimate_links ADD CONSTRAINT sales_document_estimate_links_business_id_operation_id_key UNIQUE (business_id, operation_id);
ALTER TABLE briskers.sales_document_estimate_links ADD CONSTRAINT sales_document_estimate_links_pkey PRIMARY KEY (business_id, estimate_id);
ALTER TABLE briskers.sales_document_lines ADD CONSTRAINT sales_document_lines_business_id_document_id_position_key UNIQUE (business_id, document_id, "position");
ALTER TABLE briskers.sales_document_lines ADD CONSTRAINT sales_document_lines_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.sales_document_lines ADD CONSTRAINT sales_document_lines_pkey PRIMARY KEY (id);
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_pkey PRIMARY KEY (id);
ALTER TABLE briskers.sales_line_receipt_links ADD CONSTRAINT sales_line_receipt_links_pkey PRIMARY KEY (business_id, sales_document_line_id, receipt_item_id);
ALTER TABLE briskers.sync_applied_operations ADD CONSTRAINT sync_applied_operations_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.sync_appointment_changes ADD CONSTRAINT sync_appointment_changes_pkey PRIMARY KEY (cursor);
ALTER TABLE briskers.sync_customer_changes ADD CONSTRAINT sync_customer_changes_pkey PRIMARY KEY (cursor);
ALTER TABLE briskers.sync_job_changes ADD CONSTRAINT sync_job_changes_pkey PRIMARY KEY (cursor);
ALTER TABLE briskers.sync_office_changes ADD CONSTRAINT sync_office_changes_pkey PRIMARY KEY (cursor);
ALTER TABLE briskers.vehicle_create_replay ADD CONSTRAINT vehicle_create_replay_pkey PRIMARY KEY (business_id, operation_id);
ALTER TABLE briskers.vehicle_customers ADD CONSTRAINT vehicle_customers_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.vehicle_customers ADD CONSTRAINT vehicle_customers_pkey PRIMARY KEY (id);
ALTER TABLE briskers.vehicle_private ADD CONSTRAINT vehicle_private_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.vehicle_private ADD CONSTRAINT vehicle_private_business_id_vehicle_id_key UNIQUE (business_id, vehicle_id);
ALTER TABLE briskers.vehicle_private ADD CONSTRAINT vehicle_private_pkey PRIMARY KEY (id);
ALTER TABLE briskers.vehicles ADD CONSTRAINT vehicles_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.vehicles ADD CONSTRAINT vehicles_pkey PRIMARY KEY (id);
ALTER TABLE briskers.vendor_receipt_training_samples ADD CONSTRAINT vendor_receipt_training_samples_attachment_key UNIQUE (business_id, attachment_id);
ALTER TABLE briskers.vendor_receipt_training_samples ADD CONSTRAINT vendor_receipt_training_samples_pkey PRIMARY KEY (id);
ALTER TABLE briskers.vendors ADD CONSTRAINT vendors_business_id_id_key UNIQUE (business_id, id);
ALTER TABLE briskers.vendors ADD CONSTRAINT vendors_pkey PRIMARY KEY (id);
ALTER TABLE briskers.warranty_companies ADD CONSTRAINT warranty_companies_business_id_name_key UNIQUE (business_id, name);
ALTER TABLE briskers.warranty_companies ADD CONSTRAINT warranty_companies_pkey PRIMARY KEY (id);
ALTER TABLE briskers.activity_events ADD CONSTRAINT activity_events_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointment_requests ADD CONSTRAINT appointment_requests_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointment_requests ADD CONSTRAINT appointment_requests_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointment_requests ADD CONSTRAINT appointment_requests_business_id_vehicle_id_fkey FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointment_requests ADD CONSTRAINT appointment_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_business_id_employee_id_fkey FOREIGN KEY (business_id, employee_id) REFERENCES briskers.employees(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_business_id_request_id_fkey FOREIGN KEY (business_id, request_id) REFERENCES briskers.appointment_requests(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.appointments ADD CONSTRAINT appointments_business_id_vehicle_id_fkey FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.attachments ADD CONSTRAINT attachments_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.authorizations ADD CONSTRAINT authorizations_business_id_document_id_fkey FOREIGN KEY (business_id, document_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.authorizations ADD CONSTRAINT authorizations_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.authorizations ADD CONSTRAINT authorizations_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.authorizations ADD CONSTRAINT authorizations_business_id_signature_attachment_id_fkey FOREIGN KEY (business_id, signature_attachment_id) REFERENCES briskers.attachments(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.authorizations ADD CONSTRAINT authorizations_business_id_signed_pdf_attachment_id_fkey FOREIGN KEY (business_id, signed_pdf_attachment_id) REFERENCES briskers.attachments(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.catalog_costs ADD CONSTRAINT catalog_costs_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.catalog_costs ADD CONSTRAINT catalog_costs_business_id_item_id_fkey FOREIGN KEY (business_id, item_id) REFERENCES briskers.catalog_items(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.catalog_items ADD CONSTRAINT catalog_items_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.conversation_members ADD CONSTRAINT conversation_members_business_id_conversation_id_fkey FOREIGN KEY (business_id, conversation_id) REFERENCES briskers.conversations(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.conversation_members ADD CONSTRAINT conversation_members_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.conversation_members ADD CONSTRAINT conversation_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE briskers.conversations ADD CONSTRAINT conversations_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.conversations ADD CONSTRAINT conversations_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.conversations ADD CONSTRAINT conversations_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.customer_account_requests ADD CONSTRAINT customer_account_requests_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.customer_account_requests ADD CONSTRAINT customer_account_requests_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES briskers.customers(id) ON DELETE CASCADE;
ALTER TABLE briskers.customer_contacts ADD CONSTRAINT customer_contacts_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.customer_contacts ADD CONSTRAINT customer_contacts_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.customer_note_attachments ADD CONSTRAINT customer_note_attachments_attachment_fk FOREIGN KEY (business_id, attachment_id) REFERENCES briskers.attachments(business_id, id);
ALTER TABLE briskers.customer_note_attachments ADD CONSTRAINT customer_note_attachments_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id);
ALTER TABLE briskers.customer_note_attachments ADD CONSTRAINT customer_note_attachments_note_fk FOREIGN KEY (business_id, note_id) REFERENCES briskers.customer_notes(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_customer_fk FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_found_document_fk FOREIGN KEY (business_id, found_document_id) REFERENCES briskers.sales_documents(business_id, id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_found_job_fk FOREIGN KEY (business_id, found_job_id) REFERENCES briskers.jobs(business_id, id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_repair_job_fk FOREIGN KEY (business_id, repair_job_id) REFERENCES briskers.jobs(business_id, id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_resolved_document_fk FOREIGN KEY (business_id, resolved_document_id) REFERENCES briskers.sales_documents(business_id, id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_resolved_job_fk FOREIGN KEY (business_id, resolved_job_id) REFERENCES briskers.jobs(business_id, id);
ALTER TABLE briskers.customer_notes ADD CONSTRAINT customer_notes_vehicle_fk FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id);
ALTER TABLE briskers.customer_private ADD CONSTRAINT customer_private_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.customer_private ADD CONSTRAINT customer_private_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.customer_user_links ADD CONSTRAINT customer_user_links_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.customer_user_links ADD CONSTRAINT customer_user_links_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.customer_user_links ADD CONSTRAINT customer_user_links_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE briskers.customers ADD CONSTRAINT customers_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.device_tokens ADD CONSTRAINT device_tokens_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.device_tokens ADD CONSTRAINT device_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE briskers.disclaimer_templates ADD CONSTRAINT disclaimer_templates_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.document_attachments ADD CONSTRAINT document_attachments_business_id_attachment_id_fkey FOREIGN KEY (business_id, attachment_id) REFERENCES briskers.attachments(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.document_attachments ADD CONSTRAINT document_attachments_business_id_document_id_fkey FOREIGN KEY (business_id, document_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.document_attachments ADD CONSTRAINT document_attachments_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.document_counters ADD CONSTRAINT document_counters_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.document_disclaimers ADD CONSTRAINT document_disclaimers_authorization_id_fkey FOREIGN KEY (authorization_id) REFERENCES briskers.authorizations(id) ON DELETE SET NULL;
ALTER TABLE briskers.document_disclaimers ADD CONSTRAINT document_disclaimers_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.document_disclaimers ADD CONSTRAINT document_disclaimers_document_id_fkey FOREIGN KEY (document_id) REFERENCES briskers.sales_documents(id) ON DELETE CASCADE;
ALTER TABLE briskers.document_disclaimers ADD CONSTRAINT document_disclaimers_template_id_fkey FOREIGN KEY (template_id) REFERENCES briskers.disclaimer_templates(id) ON DELETE SET NULL;
ALTER TABLE briskers.document_note_templates ADD CONSTRAINT document_note_templates_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.document_number_reuse ADD CONSTRAINT document_number_reuse_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.document_reassignment_restore ADD CONSTRAINT document_reassignment_restore_document_fk FOREIGN KEY (business_id, document_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.document_revisions ADD CONSTRAINT document_revisions_business_id_document_id_fkey FOREIGN KEY (business_id, document_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.employee_compensation ADD CONSTRAINT employee_compensation_business_id_employee_id_fkey FOREIGN KEY (business_id, employee_id) REFERENCES briskers.employees(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.employee_compensation ADD CONSTRAINT employee_compensation_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.employee_compensation ADD CONSTRAINT employee_compensation_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE briskers.employee_positions ADD CONSTRAINT employee_positions_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.employee_positions ADD CONSTRAINT employee_positions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE briskers.employee_private ADD CONSTRAINT employee_private_business_id_employee_id_fkey FOREIGN KEY (business_id, employee_id) REFERENCES briskers.employees(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.employee_private ADD CONSTRAINT employee_private_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.employee_rates ADD CONSTRAINT employee_rates_business_id_employee_id_fkey FOREIGN KEY (business_id, employee_id) REFERENCES briskers.employees(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.employee_rates ADD CONSTRAINT employee_rates_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.employees ADD CONSTRAINT employees_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.employees ADD CONSTRAINT employees_position_fk FOREIGN KEY (business_id, position_id) REFERENCES briskers.employee_positions(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.employees ADD CONSTRAINT employees_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_allocations ADD CONSTRAINT expense_allocations_business_id_category_id_fkey FOREIGN KEY (business_id, category_id) REFERENCES briskers.financial_categories(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_allocations ADD CONSTRAINT expense_allocations_business_id_document_id_fkey FOREIGN KEY (business_id, document_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_allocations ADD CONSTRAINT expense_allocations_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_allocations ADD CONSTRAINT expense_allocations_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_allocations ADD CONSTRAINT expense_allocations_business_id_transaction_id_fkey FOREIGN KEY (business_id, transaction_id) REFERENCES briskers.financial_transactions(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_attachments ADD CONSTRAINT expense_attachments_business_id_attachment_id_fkey FOREIGN KEY (business_id, attachment_id) REFERENCES briskers.attachments(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_attachments ADD CONSTRAINT expense_attachments_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_attachments ADD CONSTRAINT expense_attachments_business_id_transaction_id_fkey FOREIGN KEY (business_id, transaction_id) REFERENCES briskers.financial_transactions(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.expense_receipt_details ADD CONSTRAINT expense_receipt_details_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.expense_receipt_details ADD CONSTRAINT expense_receipt_details_business_id_transaction_id_fkey FOREIGN KEY (business_id, transaction_id) REFERENCES briskers.financial_transactions(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.expense_receipt_items ADD CONSTRAINT expense_receipt_items_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.expense_receipt_items ADD CONSTRAINT expense_receipt_items_business_id_transaction_id_fkey FOREIGN KEY (business_id, transaction_id) REFERENCES briskers.expense_receipt_details(business_id, transaction_id) ON DELETE CASCADE;
ALTER TABLE briskers.financial_accounts ADD CONSTRAINT financial_accounts_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_categories ADD CONSTRAINT financial_categories_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_categories ADD CONSTRAINT financial_categories_business_id_parent_id_fkey FOREIGN KEY (business_id, parent_id) REFERENCES briskers.financial_categories(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_business_id_account_id_currency_cod_fkey FOREIGN KEY (business_id, account_id, currency_code) REFERENCES briskers.financial_accounts(business_id, id, currency_code) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_business_id_category_id_fkey FOREIGN KEY (business_id, category_id) REFERENCES briskers.financial_categories(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_business_id_payment_method_id_fkey FOREIGN KEY (business_id, payment_method_id) REFERENCES briskers.payment_methods(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_business_id_vendor_id_fkey FOREIGN KEY (business_id, vendor_id) REFERENCES briskers.vendors(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.financial_transactions ADD CONSTRAINT financial_transactions_recurring_rule_fkey FOREIGN KEY (business_id, recurring_rule_id) REFERENCES briskers.recurring_transactions(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.import_batches ADD CONSTRAINT import_batches_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.import_issues ADD CONSTRAINT import_issues_business_id_batch_id_fkey FOREIGN KEY (business_id, batch_id) REFERENCES briskers.import_batches(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.import_issues ADD CONSTRAINT import_issues_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.import_rows ADD CONSTRAINT import_rows_business_id_batch_id_fkey FOREIGN KEY (business_id, batch_id) REFERENCES briskers.import_batches(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.import_rows ADD CONSTRAINT import_rows_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.invoice_pending_payments ADD CONSTRAINT invoice_pending_payments_business_id_account_id_fkey FOREIGN KEY (business_id, account_id) REFERENCES briskers.financial_accounts(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.invoice_pending_payments ADD CONSTRAINT invoice_pending_payments_business_id_invoice_id_fkey FOREIGN KEY (business_id, invoice_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.invoice_pending_payments ADD CONSTRAINT invoice_pending_payments_business_id_payment_method_id_fkey FOREIGN KEY (business_id, payment_method_id) REFERENCES briskers.payment_methods(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.invoice_status_styles ADD CONSTRAINT invoice_status_styles_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.item_categories ADD CONSTRAINT item_categories_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.job_assignment_requests ADD CONSTRAINT job_assignment_requests_business_id_employee_id_fkey FOREIGN KEY (business_id, employee_id) REFERENCES briskers.employees(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_assignment_requests ADD CONSTRAINT job_assignment_requests_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_assignments ADD CONSTRAINT job_assignments_business_id_employee_id_fkey FOREIGN KEY (business_id, employee_id) REFERENCES briskers.employees(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_assignments ADD CONSTRAINT job_assignments_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_assignments ADD CONSTRAINT job_assignments_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_attachments ADD CONSTRAINT job_attachments_business_id_attachment_id_fkey FOREIGN KEY (business_id, attachment_id) REFERENCES briskers.attachments(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_attachments ADD CONSTRAINT job_attachments_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_attachments ADD CONSTRAINT job_attachments_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_internal_notes ADD CONSTRAINT job_internal_notes_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_internal_notes ADD CONSTRAINT job_internal_notes_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_labor ADD CONSTRAINT job_labor_business_id_assignment_id_fkey FOREIGN KEY (business_id, assignment_id) REFERENCES briskers.job_assignments(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_labor ADD CONSTRAINT job_labor_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_pre_inspection_photos ADD CONSTRAINT job_pre_inspection_photos_business_id_attachment_id_fkey FOREIGN KEY (business_id, attachment_id) REFERENCES briskers.attachments(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_pre_inspection_photos ADD CONSTRAINT job_pre_inspection_photos_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_pre_inspection_photos ADD CONSTRAINT job_pre_inspection_photos_business_id_inspection_id_fkey FOREIGN KEY (business_id, inspection_id) REFERENCES briskers.job_pre_inspections(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.job_pre_inspections ADD CONSTRAINT job_pre_inspections_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_pre_inspections ADD CONSTRAINT job_pre_inspections_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.job_status_events ADD CONSTRAINT job_status_events_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_statuses ADD CONSTRAINT job_statuses_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_visit_assignments ADD CONSTRAINT job_visit_assignments_business_id_employee_id_fkey FOREIGN KEY (business_id, employee_id) REFERENCES briskers.employees(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_visit_assignments ADD CONSTRAINT job_visit_assignments_business_id_request_id_fkey FOREIGN KEY (business_id, request_id) REFERENCES briskers.job_assignment_requests(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_visit_assignments ADD CONSTRAINT job_visit_assignments_business_id_visit_id_fkey FOREIGN KEY (business_id, visit_id) REFERENCES briskers.job_visits(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.job_visits ADD CONSTRAINT job_visits_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.jobs ADD CONSTRAINT jobs_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.jobs ADD CONSTRAINT jobs_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.jobs ADD CONSTRAINT jobs_business_id_status_fkey FOREIGN KEY (business_id, status) REFERENCES briskers.job_statuses(business_id, code) ON DELETE RESTRICT;
ALTER TABLE briskers.jobs ADD CONSTRAINT jobs_business_id_vehicle_id_fkey FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.kiosk_disclaimers ADD CONSTRAINT kiosk_disclaimers_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.kiosk_registrations ADD CONSTRAINT kiosk_registrations_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.kiosk_registrations ADD CONSTRAINT kiosk_registrations_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES briskers.customers(id);
ALTER TABLE briskers.kiosk_registrations ADD CONSTRAINT kiosk_registrations_disclaimer_id_fkey FOREIGN KEY (disclaimer_id) REFERENCES briskers.kiosk_disclaimers(id);
ALTER TABLE briskers.kiosk_registrations ADD CONSTRAINT kiosk_registrations_job_id_fkey FOREIGN KEY (job_id) REFERENCES briskers.jobs(id);
ALTER TABLE briskers.kiosk_registrations ADD CONSTRAINT kiosk_registrations_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES briskers.vehicles(id);
ALTER TABLE briskers.legacy_links ADD CONSTRAINT legacy_links_business_id_batch_id_fkey FOREIGN KEY (business_id, batch_id) REFERENCES briskers.import_batches(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.legacy_links ADD CONSTRAINT legacy_links_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.memberships ADD CONSTRAINT memberships_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.memberships ADD CONSTRAINT memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE briskers.message_attachments ADD CONSTRAINT message_attachments_business_id_attachment_id_fkey FOREIGN KEY (business_id, attachment_id) REFERENCES briskers.attachments(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.message_attachments ADD CONSTRAINT message_attachments_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.message_attachments ADD CONSTRAINT message_attachments_business_id_message_id_fkey FOREIGN KEY (business_id, message_id) REFERENCES briskers.messages(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.messages ADD CONSTRAINT messages_business_id_conversation_id_fkey FOREIGN KEY (business_id, conversation_id) REFERENCES briskers.conversations(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.messages ADD CONSTRAINT messages_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.messages ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE briskers.notification_outbox ADD CONSTRAINT notification_outbox_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.notification_outbox ADD CONSTRAINT notification_outbox_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE briskers.payment_allocations ADD CONSTRAINT payment_allocations_business_id_document_id_fkey FOREIGN KEY (business_id, document_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.payment_allocations ADD CONSTRAINT payment_allocations_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.payment_allocations ADD CONSTRAINT payment_allocations_business_id_transaction_id_fkey FOREIGN KEY (business_id, transaction_id) REFERENCES briskers.financial_transactions(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.payment_methods ADD CONSTRAINT payment_methods_business_id_default_account_id_fkey FOREIGN KEY (business_id, default_account_id) REFERENCES briskers.financial_accounts(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.payment_methods ADD CONSTRAINT payment_methods_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.payroll_allocations ADD CONSTRAINT payroll_allocations_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.payroll_allocations ADD CONSTRAINT payroll_allocations_business_id_labor_id_fkey FOREIGN KEY (business_id, labor_id) REFERENCES briskers.job_labor(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.payroll_allocations ADD CONSTRAINT payroll_allocations_business_id_transaction_id_fkey FOREIGN KEY (business_id, transaction_id) REFERENCES briskers.financial_transactions(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.permission_overrides ADD CONSTRAINT permission_overrides_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.permission_overrides ADD CONSTRAINT permission_overrides_business_id_user_id_fkey FOREIGN KEY (business_id, user_id) REFERENCES briskers.memberships(business_id, user_id) ON DELETE RESTRICT;
ALTER TABLE briskers.permission_overrides ADD CONSTRAINT permission_overrides_permission_code_fkey FOREIGN KEY (permission_code) REFERENCES briskers.permissions(code);
ALTER TABLE briskers.quick_transaction_templates ADD CONSTRAINT quick_transaction_templates_business_id_account_id_fkey FOREIGN KEY (business_id, account_id) REFERENCES briskers.financial_accounts(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.quick_transaction_templates ADD CONSTRAINT quick_transaction_templates_business_id_category_id_fkey FOREIGN KEY (business_id, category_id) REFERENCES briskers.financial_categories(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.quick_transaction_templates ADD CONSTRAINT quick_transaction_templates_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.quick_transaction_templates ADD CONSTRAINT quick_transaction_templates_business_id_vendor_id_fkey FOREIGN KEY (business_id, vendor_id) REFERENCES briskers.vendors(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_occurrences ADD CONSTRAINT recurring_occurrences_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_occurrences ADD CONSTRAINT recurring_occurrences_business_id_rule_id_fkey FOREIGN KEY (business_id, rule_id) REFERENCES briskers.recurring_rules(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_occurrences ADD CONSTRAINT recurring_occurrences_business_id_transaction_id_fkey FOREIGN KEY (business_id, transaction_id) REFERENCES briskers.financial_transactions(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_rules ADD CONSTRAINT recurring_rules_business_id_account_id_fkey FOREIGN KEY (business_id, account_id) REFERENCES briskers.financial_accounts(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_rules ADD CONSTRAINT recurring_rules_business_id_category_id_fkey FOREIGN KEY (business_id, category_id) REFERENCES briskers.financial_categories(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_rules ADD CONSTRAINT recurring_rules_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_rules ADD CONSTRAINT recurring_rules_business_id_vendor_id_fkey FOREIGN KEY (business_id, vendor_id) REFERENCES briskers.vendors(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_transactions ADD CONSTRAINT recurring_transactions_business_id_account_id_fkey FOREIGN KEY (business_id, account_id) REFERENCES briskers.financial_accounts(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_transactions ADD CONSTRAINT recurring_transactions_business_id_category_id_fkey FOREIGN KEY (business_id, category_id) REFERENCES briskers.financial_categories(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_transactions ADD CONSTRAINT recurring_transactions_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_transactions ADD CONSTRAINT recurring_transactions_business_id_source_transaction_id_fkey FOREIGN KEY (business_id, source_transaction_id) REFERENCES briskers.financial_transactions(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.recurring_transactions ADD CONSTRAINT recurring_transactions_business_id_vendor_id_fkey FOREIGN KEY (business_id, vendor_id) REFERENCES briskers.vendors(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.role_permissions ADD CONSTRAINT role_permissions_permission_code_fkey FOREIGN KEY (permission_code) REFERENCES briskers.permissions(code);
ALTER TABLE briskers.sales_document_estimate_links ADD CONSTRAINT sales_document_estimate_links_estimate_fk FOREIGN KEY (business_id, estimate_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_document_estimate_links ADD CONSTRAINT sales_document_estimate_links_invoice_fk FOREIGN KEY (business_id, invoice_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_document_lines ADD CONSTRAINT sales_document_lines_business_id_document_id_fkey FOREIGN KEY (business_id, document_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_document_lines ADD CONSTRAINT sales_document_lines_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_document_lines ADD CONSTRAINT sales_document_lines_business_id_item_id_fkey FOREIGN KEY (business_id, item_id) REFERENCES briskers.catalog_items(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_business_id_credited_invoice_id_fkey FOREIGN KEY (business_id, credited_invoice_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_business_id_job_id_fkey FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_business_id_source_estimate_id_fkey FOREIGN KEY (business_id, source_estimate_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_business_id_vehicle_id_fkey FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.sales_documents ADD CONSTRAINT sales_documents_warranty_company_fk FOREIGN KEY (warranty_company_id) REFERENCES briskers.warranty_companies(id) ON DELETE SET NULL;
ALTER TABLE briskers.sales_line_receipt_links ADD CONSTRAINT sales_line_receipt_links_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.sales_line_receipt_links ADD CONSTRAINT sales_line_receipt_links_business_id_receipt_item_id_fkey FOREIGN KEY (business_id, receipt_item_id) REFERENCES briskers.expense_receipt_items(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.sales_line_receipt_links ADD CONSTRAINT sales_line_receipt_links_business_id_sales_document_line_i_fkey FOREIGN KEY (business_id, sales_document_line_id) REFERENCES briskers.sales_document_lines(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.sync_applied_operations ADD CONSTRAINT sync_applied_operations_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.sync_appointment_changes ADD CONSTRAINT sync_appointment_changes_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id);
ALTER TABLE briskers.sync_customer_changes ADD CONSTRAINT sync_customer_changes_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id);
ALTER TABLE briskers.sync_job_changes ADD CONSTRAINT sync_job_changes_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id);
ALTER TABLE briskers.sync_office_changes ADD CONSTRAINT sync_office_changes_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id);
ALTER TABLE briskers.vehicle_customers ADD CONSTRAINT vehicle_customers_business_id_customer_id_fkey FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.vehicle_customers ADD CONSTRAINT vehicle_customers_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.vehicle_customers ADD CONSTRAINT vehicle_customers_business_id_vehicle_id_fkey FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.vehicle_private ADD CONSTRAINT vehicle_private_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.vehicle_private ADD CONSTRAINT vehicle_private_business_id_vehicle_id_fkey FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id) ON DELETE RESTRICT;
ALTER TABLE briskers.vehicles ADD CONSTRAINT vehicles_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.vendor_receipt_training_samples ADD CONSTRAINT vendor_receipt_training_samples_attachment_fkey FOREIGN KEY (business_id, attachment_id) REFERENCES briskers.attachments(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.vendor_receipt_training_samples ADD CONSTRAINT vendor_receipt_training_samples_business_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;
ALTER TABLE briskers.vendor_receipt_training_samples ADD CONSTRAINT vendor_receipt_training_samples_vendor_fkey FOREIGN KEY (business_id, vendor_id) REFERENCES briskers.vendors(business_id, id) ON DELETE CASCADE;
ALTER TABLE briskers.vendors ADD CONSTRAINT vendors_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT;
ALTER TABLE briskers.vendors ADD CONSTRAINT vendors_default_category_id_fkey FOREIGN KEY (default_category_id) REFERENCES briskers.financial_categories(id) ON DELETE SET NULL;
ALTER TABLE briskers.warranty_companies ADD CONSTRAINT warranty_companies_business_id_fkey FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE;

CREATE FUNCTION briskers.is_owner(b uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT EXISTS(SELECT 1 FROM briskers.memberships WHERE business_id=b AND user_id=auth.uid() AND active AND role_code='owner')
$$;
CREATE FUNCTION briskers.is_member(b uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT EXISTS(SELECT 1 FROM briskers.memberships WHERE business_id=b AND user_id=auth.uid() AND active)
$$;
CREATE FUNCTION briskers.require_permission(b uuid,p text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF NOT briskers.is_member(b) THEN RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501'; END IF; END $$;
INSERT INTO auth.users VALUES('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002');
INSERT INTO briskers.businesses(id,name) VALUES('10000000-0000-0000-0000-000000000001','Synthetic A'),('10000000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO briskers.memberships(business_id,user_id,display_name,role_code) VALUES
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Owner A','owner'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','Mechanic A','mechanic');
INSERT INTO briskers.customers(id,business_id,display_name) VALUES
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Synthetic customer');
INSERT INTO briskers.vehicles(id,business_id) VALUES('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
INSERT INTO briskers.job_statuses(business_id,code,name,color_hex,icon_key) VALUES('10000000-0000-0000-0000-000000000001','open','Open','#000000','work');
INSERT INTO briskers.jobs(id,business_id,customer_id,job_number,title) VALUES
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','J-100','Synthetic test'),
 ('40000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','J-7','Protected sentinel'),
 ('40000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','J-200','Unrelated sentinel');
INSERT INTO briskers.sales_documents(id,business_id,customer_id,job_id,kind) VALUES
 ('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','invoice'),
 ('50000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','estimate'),
 ('50000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000008','estimate');
INSERT INTO briskers.sales_document_lines(id,business_id,document_id,position,name) VALUES
 ('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',1,'Synthetic line');
INSERT INTO briskers.document_disclaimers(business_id,document_id,title,body,signature_required) VALUES
 ('10000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000002','Synthetic disclaimer','Text',false);
INSERT INTO briskers.job_visits(business_id,job_id,visit_number,reason) VALUES
 ('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',1,'Initial visit');
INSERT INTO briskers.job_status_events(business_id,job_id,to_status,note) VALUES
 ('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','open','Job created');
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
