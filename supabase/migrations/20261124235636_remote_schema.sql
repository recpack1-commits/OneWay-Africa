SET local check_function_bodies = off;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "authenticated";

REVOKE ALL ON SCHEMA "public" FROM PUBLIC;

REVOKE ALL ON SCHEMA "public" FROM "anon";

CREATE SCHEMA "private";

CREATE TABLE "public"."app_users" (
  "id"             uuid                     NOT NULL,
  "display_name"   text                     NOT NULL,
  "status"         text                     NOT NULL DEFAULT 'active'::text,
  "deactivated_at" timestamp with time zone,
  "deactivated_by" uuid,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "app_users_pkey" PRIMARY KEY (id),
  CONSTRAINT "app_users_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'suspended'::text])))
);

ALTER TABLE "public"."app_users"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."app_users" FROM "anon";

CREATE TABLE "public"."audit_logs" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "actor_user_id" uuid,
  "action"        text                     NOT NULL,
  "entity_type"   text                     NOT NULL,
  "entity_id"     uuid,
  "before_values" jsonb,
  "after_values"  jsonb,
  "request_id"    uuid,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "audit_logs_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."audit_logs"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."audit_logs" FROM "anon";

CREATE TABLE "public"."church_plants" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "outreach_id"         uuid,
  "missionary_id"       uuid                     NOT NULL,
  "community_id"        uuid                     NOT NULL,
  "partner_ministry_id" uuid,
  "church_name"         text,
  "pastor_name"         text,
  "pastor_contact"      text,
  "details"             text,
  "status"              text                     NOT NULL DEFAULT 'reported'::text,
  "planted_date"        date,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "church_plants_pkey" PRIMARY KEY (id),
  CONSTRAINT "church_plants_status_check" CHECK ((status = ANY (ARRAY['reported'::text, 'under_review'::text, 'confirmed'::text, 'rejected'::text])))
);

ALTER TABLE "public"."church_plants"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."church_plants" FROM "anon";

CREATE TABLE "public"."communities" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "district_id" uuid                     NOT NULL,
  "code"        text,
  "name"        text                     NOT NULL,
  "is_active"   boolean                  NOT NULL DEFAULT true,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "communities_district_id_code_key" UNIQUE (district_id, code),
  CONSTRAINT "communities_district_id_name_key" UNIQUE (district_id, name),
  CONSTRAINT "communities_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."communities"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."communities" FROM "anon";

CREATE TABLE "public"."disbursement_confirmations" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "disbursement_id" uuid                     NOT NULL,
  "confirmed_by"    uuid                     NOT NULL,
  "decision"        text                     NOT NULL,
  "amount_received" numeric(14,2),
  "received_date"   date,
  "notes"           text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "disbursement_confirmations_amount_received_check" CHECK ((amount_received >= (0)::numeric)),
  CONSTRAINT "disbursement_confirmations_check" CHECK (((decision <> 'confirm'::text) OR ((amount_received IS NOT NULL) AND (received_date IS NOT NULL)))),
  CONSTRAINT "disbursement_confirmations_decision_check" CHECK ((decision = ANY (ARRAY['confirm'::text, 'dispute'::text]))),
  CONSTRAINT "disbursement_confirmations_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."disbursement_confirmations"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."disbursement_confirmations" FROM "anon";

CREATE TABLE "public"."disbursement_receipts" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "disbursement_id" uuid                     NOT NULL,
  "file_asset_id"   uuid                     NOT NULL,
  "uploaded_by"     uuid                     NOT NULL,
  "uploaded_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "disbursement_receipts_disbursement_id_file_asset_id_key" UNIQUE (disbursement_id, file_asset_id),
  CONSTRAINT "disbursement_receipts_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."disbursement_receipts"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."disbursement_receipts" FROM "anon";

CREATE TABLE "public"."disbursements" (
  "id"                    uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "reference"             text                     NOT NULL,
  "missionary_id"         uuid                     NOT NULL,
  "reporting_period_id"   uuid                     NOT NULL,
  "amount_sent"           numeric(14,2)            NOT NULL,
  "currency"              character(3)             NOT NULL DEFAULT 'GHS'::bpchar,
  "sent_date"             date                     NOT NULL,
  "payment_method"        text                     NOT NULL,
  "transaction_reference" text,
  "status"                text                     NOT NULL DEFAULT 'awaiting_confirmation'::text,
  "amount_received"       numeric(14,2),
  "received_date"         date,
  "confirmation_notes"    text,
  "exchange_rate_to_ghs"  numeric(18,8),
  "notes"                 text,
  "created_by"            uuid                     NOT NULL,
  "created_at"            timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"            timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "disbursements_amount_received_check" CHECK ((amount_received >= (0)::numeric)),
  CONSTRAINT "disbursements_amount_sent_check" CHECK ((amount_sent > (0)::numeric)),
  CONSTRAINT "disbursements_check" CHECK (((status <> 'confirmed'::text) OR ((amount_received IS NOT NULL) AND (received_date IS NOT NULL)))),
  CONSTRAINT "disbursements_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "disbursements_exchange_rate_to_ghs_check" CHECK ((exchange_rate_to_ghs > (0)::numeric)),
  CONSTRAINT "disbursements_pkey" PRIMARY KEY (id),
  CONSTRAINT "disbursements_reference_key" UNIQUE (reference),
  CONSTRAINT "disbursements_status_check" CHECK ((status = ANY (ARRAY['awaiting_confirmation'::text, 'confirmed'::text, 'disputed'::text, 'cancelled'::text])))
);

ALTER TABLE "public"."disbursements"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."disbursements" FROM "anon";

CREATE TABLE "public"."districts" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "code"       text,
  "name"       text                     NOT NULL,
  "is_active"  boolean                  NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "districts_code_key" UNIQUE (code),
  CONSTRAINT "districts_name_key" UNIQUE (name),
  CONSTRAINT "districts_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."districts"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."districts" FROM "anon";

CREATE TABLE "public"."expense_categories" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "code"             text                     NOT NULL,
  "name"             text                     NOT NULL,
  "is_active"        boolean                  NOT NULL DEFAULT true,
  "receipt_required" boolean                  NOT NULL DEFAULT true,
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "expense_categories_code_key" UNIQUE (code),
  CONSTRAINT "expense_categories_name_key" UNIQUE (name),
  CONSTRAINT "expense_categories_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."expense_categories"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."expense_categories" FROM "anon";

CREATE TABLE "public"."expense_receipts" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "expense_id"    uuid                     NOT NULL,
  "file_asset_id" uuid                     NOT NULL,
  "uploaded_by"   uuid                     NOT NULL,
  "uploaded_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "expense_receipts_expense_id_file_asset_id_key" UNIQUE (expense_id, file_asset_id),
  CONSTRAINT "expense_receipts_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."expense_receipts"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."expense_receipts" FROM "anon";

CREATE TABLE "public"."expense_reviews" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "expense_id"      uuid                     NOT NULL,
  "reviewer_id"     uuid                     NOT NULL,
  "decision"        text                     NOT NULL,
  "comments"        text,
  "previous_status" text                     NOT NULL,
  "new_status"      text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "expense_reviews_decision_check" CHECK ((decision = ANY (ARRAY['approve'::text, 'reject'::text, 'request_clarification'::text]))),
  CONSTRAINT "expense_reviews_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."expense_reviews"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."expense_reviews" FROM "anon";

CREATE TABLE "public"."expenses" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "missionary_id"        uuid                     NOT NULL,
  "reporting_period_id"  uuid                     NOT NULL,
  "expense_category_id"  uuid                     NOT NULL,
  "expense_date"         date                     NOT NULL,
  "amount"               numeric(14,2)            NOT NULL,
  "currency"             character(3)             NOT NULL DEFAULT 'GHS'::bpchar,
  "exchange_rate_to_ghs" numeric(18,8),
  "description"          text                     NOT NULL,
  "status"               text                     NOT NULL DEFAULT 'draft'::text,
  "submitted_at"         timestamp with time zone,
  "created_by"           uuid                     NOT NULL,
  "client_submission_id" uuid,
  "created_at"           timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"           timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "expenses_amount_check" CHECK ((amount > (0)::numeric)),
  CONSTRAINT "expenses_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "expenses_exchange_rate_to_ghs_check" CHECK ((exchange_rate_to_ghs > (0)::numeric)),
  CONSTRAINT "expenses_missionary_id_client_submission_id_key" UNIQUE (missionary_id, client_submission_id),
  CONSTRAINT "expenses_pkey" PRIMARY KEY (id),
  CONSTRAINT "expenses_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'queried'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))
);

ALTER TABLE "public"."expenses"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."expenses" FROM "anon";

CREATE TABLE "public"."file_assets" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "bucket_id"         text                     NOT NULL DEFAULT 'oneway-private'::text,
  "object_path"       text                     NOT NULL,
  "original_filename" text                     NOT NULL,
  "content_type"      text                     NOT NULL,
  "size_bytes"        bigint                   NOT NULL,
  "checksum_sha256"   text,
  "upload_status"     text                     NOT NULL DEFAULT 'pending'::text,
  "uploaded_by"       uuid                     NOT NULL,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  "deleted_at"        timestamp with time zone,
  CONSTRAINT "file_assets_bucket_id_check" CHECK ((bucket_id = 'oneway-private'::text)),
  CONSTRAINT "file_assets_object_path_key" UNIQUE (object_path),
  CONSTRAINT "file_assets_pkey" PRIMARY KEY (id),
  CONSTRAINT "file_assets_size_bytes_check" CHECK ((size_bytes >= 0)),
  CONSTRAINT "file_assets_upload_status_check" CHECK ((upload_status = ANY (ARRAY['pending'::text, 'uploaded'::text, 'failed'::text, 'quarantined'::text])))
);

ALTER TABLE "public"."file_assets"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."file_assets" FROM "anon";

CREATE TABLE "public"."financial_adjustments" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "missionary_id"       uuid                     NOT NULL,
  "reporting_period_id" uuid                     NOT NULL,
  "disbursement_id"     uuid,
  "expense_id"          uuid,
  "adjustment_type"     text                     NOT NULL,
  "amount"              numeric(14,2)            NOT NULL,
  "currency"            character(3)             NOT NULL DEFAULT 'GHS'::bpchar,
  "reason"              text                     NOT NULL,
  "status"              text                     NOT NULL DEFAULT 'pending'::text,
  "requested_by"        uuid                     NOT NULL,
  "approved_by"         uuid,
  "approved_at"         timestamp with time zone,
  "reversal_of_id"      uuid,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "financial_adjustments_adjustment_type_check" CHECK ((adjustment_type = ANY (ARRAY['correction'::text, 'reimbursement'::text, 'reversal'::text, 'other'::text]))),
  CONSTRAINT "financial_adjustments_amount_check" CHECK ((amount <> (0)::numeric)),
  CONSTRAINT "financial_adjustments_check1" CHECK (((status <> 'approved'::text) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL)))),
  CONSTRAINT "financial_adjustments_check" CHECK ((num_nonnulls(disbursement_id, expense_id) = 1)),
  CONSTRAINT "financial_adjustments_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "financial_adjustments_pkey" PRIMARY KEY (id),
  CONSTRAINT "financial_adjustments_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);

ALTER TABLE "public"."financial_adjustments"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."financial_adjustments" FROM "anon";

CREATE TABLE "public"."generated_reports" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "report_type"         text                     NOT NULL,
  "reporting_period_id" uuid,
  "filters"             jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "status"              text                     NOT NULL DEFAULT 'queued'::text,
  "file_asset_id"       uuid,
  "created_by"          uuid                     NOT NULL,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "generated_at"        timestamp with time zone,
  CONSTRAINT "generated_reports_pkey" PRIMARY KEY (id),
  CONSTRAINT "generated_reports_status_check" CHECK ((status = ANY (ARRAY['queued'::text, 'generating'::text, 'ready'::text, 'failed'::text])))
);

ALTER TABLE "public"."generated_reports"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."generated_reports" FROM "anon";

CREATE TABLE "public"."inventory_adjustments" (
  "id"                    uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "transaction_header_id" uuid                     NOT NULL,
  "reason"                text                     NOT NULL,
  "adjustment_type"       text                     NOT NULL,
  "requested_by"          uuid                     NOT NULL,
  "approved_by"           uuid,
  "approved_at"           timestamp with time zone,
  "created_at"            timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_adjustments_adjustment_type_check" CHECK ((adjustment_type = ANY (ARRAY['correction'::text, 'loss'::text, 'damage'::text, 'found'::text, 'other'::text]))),
  CONSTRAINT "inventory_adjustments_check" CHECK (((approved_by IS NULL) = (approved_at IS NULL))),
  CONSTRAINT "inventory_adjustments_pkey" PRIMARY KEY (id),
  CONSTRAINT "inventory_adjustments_transaction_header_id_key" UNIQUE (transaction_header_id)
);

ALTER TABLE "public"."inventory_adjustments"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."inventory_adjustments" FROM "anon";

CREATE TABLE "public"."inventory_assets" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inventory_item_id" uuid                     NOT NULL,
  "serial_number"     text                     NOT NULL,
  "asset_status"      text                     NOT NULL DEFAULT 'active'::text,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_assets_asset_status_check" CHECK ((asset_status = ANY (ARRAY['active'::text, 'damaged'::text, 'retired'::text, 'missing'::text]))),
  CONSTRAINT "inventory_assets_pkey" PRIMARY KEY (id),
  CONSTRAINT "inventory_assets_serial_number_key" UNIQUE (serial_number)
);

ALTER TABLE "public"."inventory_assets"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."inventory_assets" FROM "anon";

CREATE TABLE "public"."inventory_batches" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "inventory_item_id" uuid                     NOT NULL,
  "language_id"       uuid                     NOT NULL,
  "batch_code"        text                     NOT NULL,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_batches_inventory_item_id_language_id_batch_code_key" UNIQUE (inventory_item_id, language_id, batch_code),
  CONSTRAINT "inventory_batches_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."inventory_batches"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."inventory_batches" FROM "anon";

CREATE TABLE "public"."inventory_items" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "sku"             text                     NOT NULL,
  "item_type"       text                     NOT NULL,
  "name"            text                     NOT NULL,
  "serial_tracking" boolean                  NOT NULL DEFAULT false,
  "is_active"       boolean                  NOT NULL DEFAULT true,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_items_item_type_check" CHECK ((item_type = ANY (ARRAY['solar_audio_device'::text, 'sd_card'::text]))),
  CONSTRAINT "inventory_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "inventory_items_sku_key" UNIQUE (sku)
);

ALTER TABLE "public"."inventory_items"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."inventory_items" FROM "anon";

CREATE TABLE "public"."inventory_locations" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "location_type" text                     NOT NULL,
  "missionary_id" uuid,
  "name"          text                     NOT NULL,
  "is_active"     boolean                  NOT NULL DEFAULT true,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_locations_check" CHECK (((location_type = 'missionary'::text) = (missionary_id IS NOT NULL))),
  CONSTRAINT "inventory_locations_location_type_check" CHECK ((location_type = ANY (ARRAY['office'::text, 'missionary'::text, 'in_transit'::text]))),
  CONSTRAINT "inventory_locations_missionary_id_key" UNIQUE (missionary_id),
  CONSTRAINT "inventory_locations_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."inventory_locations"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."inventory_locations" FROM "anon";

CREATE TABLE "public"."inventory_transaction_headers" (
  "id"                      uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "transaction_type"        text                     NOT NULL,
  "effective_at"            timestamp with time zone NOT NULL,
  "source_location_id"      uuid,
  "destination_location_id" uuid,
  "transfer_id"             uuid,
  "opening_balance_id"      uuid,
  "status"                  text                     NOT NULL DEFAULT 'posted'::text,
  "created_by"              uuid                     NOT NULL,
  "idempotency_key"         uuid                     NOT NULL,
  "reversal_of_id"          uuid,
  "posted_at"               timestamp with time zone NOT NULL DEFAULT now(),
  "created_at"              timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_transaction_headers_check" CHECK ((source_location_id IS DISTINCT FROM destination_location_id)),
  CONSTRAINT "inventory_transaction_headers_idempotency_key_key" UNIQUE (idempotency_key),
  CONSTRAINT "inventory_transaction_headers_pkey" PRIMARY KEY (id),
  CONSTRAINT "inventory_transaction_headers_status_check" CHECK ((status = ANY (ARRAY['posted'::text, 'reversed'::text]))),
  CONSTRAINT "inventory_transaction_headers_transaction_type_check"
    CHECK ((transaction_type = ANY (ARRAY['opening'::text, 'receipt'::text, 'dispatch'::text, 'transfer_out'::text, 'transfer_in'::text, 'adjustment'::text, 'reversal'::text])))
);

ALTER TABLE "public"."inventory_transaction_headers"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."inventory_transaction_headers" FROM "anon";

CREATE TABLE "public"."inventory_transaction_lines" (
  "id"                    uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "transaction_header_id" uuid                     NOT NULL,
  "inventory_item_id"     uuid                     NOT NULL,
  "language_id"           uuid,
  "batch_id"              uuid,
  "inventory_asset_id"    uuid,
  "quantity"              integer                  NOT NULL,
  "device_condition"      text,
  "created_at"            timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_transaction_lines_check" CHECK (((inventory_asset_id IS NULL) OR (quantity = 1))),
  CONSTRAINT "inventory_transaction_lines_device_condition_check"
    CHECK ((device_condition = ANY (ARRAY['new'::text, 'good'::text, 'fair'::text, 'damaged'::text, 'unknown'::text]))),
  CONSTRAINT "inventory_transaction_lines_pkey" PRIMARY KEY (id),
  CONSTRAINT "inventory_transaction_lines_quantity_check" CHECK ((quantity > 0))
);

ALTER TABLE "public"."inventory_transaction_lines"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."inventory_transaction_lines" FROM "anon";

CREATE TABLE "public"."inventory_transfers" (
  "id"                      uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "reference"               text                     NOT NULL,
  "source_location_id"      uuid                     NOT NULL,
  "destination_location_id" uuid                     NOT NULL,
  "initiated_by"            uuid                     NOT NULL,
  "recipient_user_id"       uuid,
  "status"                  text                     NOT NULL DEFAULT 'requested'::text,
  "notes"                   text,
  "client_submission_id"    uuid,
  "created_at"              timestamp with time zone NOT NULL DEFAULT now(),
  "sent_at"                 timestamp with time zone,
  "updated_at"              timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inventory_transfers_check" CHECK ((source_location_id <> destination_location_id)),
  CONSTRAINT "inventory_transfers_initiated_by_client_submission_id_key" UNIQUE (initiated_by, client_submission_id),
  CONSTRAINT "inventory_transfers_pkey" PRIMARY KEY (id),
  CONSTRAINT "inventory_transfers_reference_key" UNIQUE (reference),
  CONSTRAINT "inventory_transfers_status_check"
    CHECK ((status = ANY (ARRAY['requested'::text, 'in_transit'::text, 'partially_received'::text, 'confirmed'::text, 'disputed'::text, 'cancelled'::text])))
);

ALTER TABLE "public"."inventory_transfers"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."inventory_transfers" FROM "anon";

CREATE TABLE "public"."languages" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "code"       text                     NOT NULL,
  "name"       text                     NOT NULL,
  "is_active"  boolean                  NOT NULL DEFAULT true,
  "sort_order" integer                  NOT NULL DEFAULT 0,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "languages_code_check" CHECK (((length(TRIM(BOTH FROM code)) >= 2) AND (length(TRIM(BOTH FROM code)) <= 12))),
  CONSTRAINT "languages_code_key" UNIQUE (code),
  CONSTRAINT "languages_name_check" CHECK ((length(TRIM(BOTH FROM name)) > 0)),
  CONSTRAINT "languages_name_key" UNIQUE (name),
  CONSTRAINT "languages_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."languages"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."languages" FROM "anon";

CREATE TABLE "public"."missionaries" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "app_user_id"  uuid,
  "district_id"  uuid,
  "display_name" text                     NOT NULL,
  "phone"        text,
  "status"       text                     NOT NULL DEFAULT 'active'::text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "missionaries_app_user_id_key" UNIQUE (app_user_id),
  CONSTRAINT "missionaries_pkey" PRIMARY KEY (id),
  CONSTRAINT "missionaries_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])))
);

ALTER TABLE "public"."missionaries"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."missionaries" FROM "anon";

CREATE TABLE "public"."notifications" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "recipient_user_id" uuid                     NOT NULL,
  "notification_type" text                     NOT NULL,
  "title"             text                     NOT NULL,
  "body"              text                     NOT NULL,
  "safe_metadata"     jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  "read_at"           timestamp with time zone,
  CONSTRAINT "notifications_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."notifications"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."notifications" FROM "anon";

CREATE TABLE "public"."opening_balance_lines" (
  "id"                 uuid    NOT NULL DEFAULT gen_random_uuid(),
  "opening_balance_id" uuid    NOT NULL,
  "location_id"        uuid    NOT NULL,
  "inventory_item_id"  uuid    NOT NULL,
  "language_id"        uuid,
  "batch_id"           uuid,
  "inventory_asset_id" uuid,
  "quantity"           integer NOT NULL,
  "notes"              text,
  CONSTRAINT "opening_balance_lines_check" CHECK (((inventory_asset_id IS NULL) OR (quantity = 1))),
  CONSTRAINT "opening_balance_lines_pkey" PRIMARY KEY (id),
  CONSTRAINT "opening_balance_lines_quantity_check" CHECK ((quantity > 0))
);

ALTER TABLE "public"."opening_balance_lines"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."opening_balance_lines" FROM "anon";

CREATE TABLE "public"."opening_balances" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "effective_date" date                     NOT NULL DEFAULT '2027-01-01'::date,
  "status"         text                     NOT NULL DEFAULT 'draft'::text,
  "verified_by"    uuid,
  "verified_at"    timestamp with time zone,
  "created_by"     uuid                     NOT NULL,
  "notes"          text,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "opening_balances_check" CHECK (((status <> ALL (ARRAY['verified'::text, 'posted'::text])) OR ((verified_by IS NOT NULL) AND (verified_at IS NOT NULL)))),
  CONSTRAINT "opening_balances_effective_date_check" CHECK ((effective_date = '2027-01-01'::date)),
  CONSTRAINT "opening_balances_pkey" PRIMARY KEY (id),
  CONSTRAINT "opening_balances_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'verified'::text, 'posted'::text, 'rejected'::text])))
);

ALTER TABLE "public"."opening_balances"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."opening_balances" FROM "anon";

CREATE TABLE "public"."outreach_photos" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "outreach_id"       uuid                     NOT NULL,
  "file_asset_id"     uuid                     NOT NULL,
  "caption"           text,
  "consent_status"    text                     NOT NULL DEFAULT 'not_recorded'::text,
  "publication_scope" text                     NOT NULL DEFAULT 'internal'::text,
  "uploaded_by"       uuid                     NOT NULL,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "outreach_photos_consent_status_check" CHECK ((consent_status = ANY (ARRAY['not_recorded'::text, 'granted'::text, 'denied'::text, 'withdrawn'::text]))),
  CONSTRAINT "outreach_photos_outreach_id_file_asset_id_key" UNIQUE (outreach_id, file_asset_id),
  CONSTRAINT "outreach_photos_pkey" PRIMARY KEY (id),
  CONSTRAINT "outreach_photos_publication_scope_check" CHECK ((publication_scope = ANY (ARRAY['internal'::text, 'external'::text])))
);

ALTER TABLE "public"."outreach_photos"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."outreach_photos" FROM "anon";

CREATE TABLE "public"."outreach_reviews" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "outreach_id"     uuid                     NOT NULL,
  "reviewer_id"     uuid                     NOT NULL,
  "decision"        text                     NOT NULL,
  "comments"        text,
  "previous_status" text                     NOT NULL,
  "new_status"      text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "outreach_reviews_decision_check" CHECK ((decision = ANY (ARRAY['approve'::text, 'reject'::text, 'request_clarification'::text]))),
  CONSTRAINT "outreach_reviews_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."outreach_reviews"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."outreach_reviews" FROM "anon";

CREATE TABLE "public"."outreaches" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "missionary_id"        uuid                     NOT NULL,
  "community_id"         uuid                     NOT NULL,
  "people_group_id"      uuid,
  "partner_ministry_id"  uuid,
  "outreach_date"        date                     NOT NULL,
  "media_used"           text,
  "attendance"           integer                  NOT NULL DEFAULT 0,
  "reported_conversions" integer                  NOT NULL DEFAULT 0,
  "church_planted"       boolean                  NOT NULL DEFAULT false,
  "pastor_name"          text,
  "pastor_contact"       text,
  "details"              text,
  "status"               text                     NOT NULL DEFAULT 'draft'::text,
  "submitted_at"         timestamp with time zone,
  "created_by"           uuid                     NOT NULL,
  "client_submission_id" uuid,
  "created_at"           timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"           timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "outreaches_attendance_check" CHECK ((attendance >= 0)),
  CONSTRAINT "outreaches_missionary_id_client_submission_id_key" UNIQUE (missionary_id, client_submission_id),
  CONSTRAINT "outreaches_pkey" PRIMARY KEY (id),
  CONSTRAINT "outreaches_reported_conversions_check" CHECK ((reported_conversions >= 0)),
  CONSTRAINT "outreaches_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'queried'::text, 'approved'::text, 'rejected'::text])))
);

ALTER TABLE "public"."outreaches"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."outreaches" FROM "anon";

CREATE TABLE "public"."partner_ministries" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "name"          text                     NOT NULL,
  "contact_name"  text,
  "contact_phone" text,
  "contact_email" text,
  "is_active"     boolean                  NOT NULL DEFAULT true,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "partner_ministries_name_key" UNIQUE (name),
  CONSTRAINT "partner_ministries_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."partner_ministries"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."partner_ministries" FROM "anon";

CREATE TABLE "public"."people_groups" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "code"       text,
  "name"       text                     NOT NULL,
  "is_active"  boolean                  NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "people_groups_code_key" UNIQUE (code),
  CONSTRAINT "people_groups_name_key" UNIQUE (name),
  CONSTRAINT "people_groups_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."people_groups"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."people_groups" FROM "anon";

CREATE TABLE "public"."permissions" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "code"         text                     NOT NULL,
  "module"       text                     NOT NULL,
  "description"  text                     NOT NULL,
  "is_sensitive" boolean                  NOT NULL DEFAULT false,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "permissions_code_key" UNIQUE (code),
  CONSTRAINT "permissions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."permissions"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."permissions" FROM "anon";

CREATE TABLE "public"."report_approvals" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "generated_report_id" uuid                     NOT NULL,
  "reviewer_id"         uuid                     NOT NULL,
  "decision"            text                     NOT NULL,
  "comments"            text,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "report_approvals_decision_check" CHECK ((decision = ANY (ARRAY['approve'::text, 'reject'::text, 'request_changes'::text]))),
  CONSTRAINT "report_approvals_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."report_approvals"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."report_approvals" FROM "anon";

CREATE TABLE "public"."reporting_periods" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "period_type"   text                     NOT NULL,
  "start_date"    date                     NOT NULL,
  "end_date"      date                     NOT NULL,
  "label"         text                     NOT NULL,
  "year"          integer                  NOT NULL,
  "month_number"  integer,
  "period_number" integer,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "reporting_periods_check1" CHECK ((((period_type = 'month'::text) AND (month_number IS NOT NULL)) OR ((period_type <> 'month'::text) AND (month_number IS NULL)))),
  CONSTRAINT "reporting_periods_check" CHECK ((end_date >= start_date)),
  CONSTRAINT "reporting_periods_month_number_check" CHECK (((month_number >= 1) AND (month_number <= 12))),
  CONSTRAINT "reporting_periods_period_number_check" CHECK (((period_number >= 1) AND (period_number <= 4))),
  CONSTRAINT "reporting_periods_period_type_check" CHECK ((period_type = ANY (ARRAY['month'::text, 'quarter'::text, 'half_year'::text, 'year'::text]))),
  CONSTRAINT "reporting_periods_period_type_start_date_end_date_key" UNIQUE (period_type, start_date, end_date),
  CONSTRAINT "reporting_periods_pkey" PRIMARY KEY (id),
  CONSTRAINT "reporting_periods_year_check" CHECK (((year >= 2027) AND (year <= 2100)))
);

ALTER TABLE "public"."reporting_periods"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."reporting_periods" FROM "anon";

CREATE TABLE "public"."role_permissions" (
  "role_id"       uuid                     NOT NULL,
  "permission_id" uuid                     NOT NULL,
  "assigned_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "assigned_by"   uuid,
  CONSTRAINT "role_permissions_pkey" PRIMARY KEY (role_id, permission_id)
);

ALTER TABLE "public"."role_permissions"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."role_permissions" FROM "anon";

CREATE TABLE "public"."roles" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "code"           text                     NOT NULL,
  "name"           text                     NOT NULL,
  "description"    text,
  "is_system_role" boolean                  NOT NULL DEFAULT true,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "roles_code_key" UNIQUE (code),
  CONSTRAINT "roles_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."roles"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."roles" FROM "anon";

CREATE TABLE "public"."sync_records" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"              uuid                     NOT NULL,
  "client_submission_id" uuid                     NOT NULL,
  "entity_type"          text                     NOT NULL,
  "entity_id"            uuid,
  "payload_hash"         text,
  "status"               text                     NOT NULL DEFAULT 'received'::text,
  "safe_error"           text,
  "received_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "applied_at"           timestamp with time zone,
  CONSTRAINT "sync_records_pkey" PRIMARY KEY (id),
  CONSTRAINT "sync_records_status_check" CHECK ((status = ANY (ARRAY['received'::text, 'processing'::text, 'applied'::text, 'failed'::text, 'conflict'::text]))),
  CONSTRAINT "sync_records_user_id_client_submission_id_key" UNIQUE (user_id, client_submission_id)
);

ALTER TABLE "public"."sync_records"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."sync_records" FROM "anon";

CREATE TABLE "public"."system_settings" (
  "setting_key"   text                     NOT NULL,
  "setting_value" jsonb                    NOT NULL,
  "description"   text,
  "updated_by"    uuid,
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "system_settings_pkey" PRIMARY KEY (setting_key)
);

ALTER TABLE "public"."system_settings"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."system_settings" FROM "anon";

CREATE TABLE "public"."testimonies" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "missionary_id"        uuid                     NOT NULL,
  "outreach_id"          uuid,
  "community_id"         uuid,
  "testimony_text"       text                     NOT NULL,
  "status"               text                     NOT NULL DEFAULT 'draft'::text,
  "consent_status"       text                     NOT NULL DEFAULT 'not_recorded'::text,
  "consent_scope"        text                     NOT NULL DEFAULT 'internal'::text,
  "consent_recorded_by"  uuid,
  "consent_recorded_at"  timestamp with time zone,
  "is_featured"          boolean                  NOT NULL DEFAULT false,
  "submitted_at"         timestamp with time zone,
  "created_by"           uuid                     NOT NULL,
  "client_submission_id" uuid,
  "created_at"           timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"           timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "testimonies_check" CHECK (((NOT is_featured) OR ((status = 'approved'::text) AND (consent_status = 'granted'::text) AND (consent_scope = 'external'::text)))),
  CONSTRAINT "testimonies_consent_scope_check" CHECK ((consent_scope = ANY (ARRAY['internal'::text, 'external'::text]))),
  CONSTRAINT "testimonies_consent_status_check" CHECK ((consent_status = ANY (ARRAY['not_recorded'::text, 'granted'::text, 'denied'::text, 'withdrawn'::text]))),
  CONSTRAINT "testimonies_missionary_id_client_submission_id_key" UNIQUE (missionary_id, client_submission_id),
  CONSTRAINT "testimonies_pkey" PRIMARY KEY (id),
  CONSTRAINT "testimonies_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'queried'::text, 'approved'::text, 'rejected'::text])))
);

ALTER TABLE "public"."testimonies"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."testimonies" FROM "anon";

CREATE TABLE "public"."testimony_media" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "testimony_id"  uuid                     NOT NULL,
  "file_asset_id" uuid                     NOT NULL,
  "caption"       text,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "testimony_media_pkey" PRIMARY KEY (id),
  CONSTRAINT "testimony_media_testimony_id_file_asset_id_key" UNIQUE (testimony_id, file_asset_id)
);

ALTER TABLE "public"."testimony_media"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."testimony_media" FROM "anon";

CREATE TABLE "public"."testimony_reviews" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "testimony_id"    uuid                     NOT NULL,
  "reviewer_id"     uuid                     NOT NULL,
  "decision"        text                     NOT NULL,
  "comments"        text,
  "previous_status" text                     NOT NULL,
  "new_status"      text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "testimony_reviews_decision_check" CHECK ((decision = ANY (ARRAY['approve'::text, 'reject'::text, 'request_clarification'::text]))),
  CONSTRAINT "testimony_reviews_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."testimony_reviews"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."testimony_reviews" FROM "anon";

CREATE TABLE "public"."transfer_confirmations" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "transfer_id"  uuid                     NOT NULL,
  "confirmed_by" uuid                     NOT NULL,
  "decision"     text                     NOT NULL,
  "notes"        text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "transfer_confirmations_decision_check" CHECK ((decision = ANY (ARRAY['accept'::text, 'partial'::text, 'dispute'::text]))),
  CONSTRAINT "transfer_confirmations_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."transfer_confirmations"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."transfer_confirmations" FROM "anon";

CREATE TABLE "public"."transfer_items" (
  "id"                 uuid    NOT NULL DEFAULT gen_random_uuid(),
  "transfer_id"        uuid    NOT NULL,
  "inventory_item_id"  uuid    NOT NULL,
  "language_id"        uuid,
  "batch_id"           uuid,
  "inventory_asset_id" uuid,
  "quantity_sent"      integer NOT NULL,
  "quantity_received"  integer NOT NULL DEFAULT 0,
  "notes"              text,
  CONSTRAINT "transfer_items_check1" CHECK (((inventory_asset_id IS NULL) OR (quantity_sent = 1))),
  CONSTRAINT "transfer_items_check" CHECK (((quantity_received >= 0) AND (quantity_received <= quantity_sent))),
  CONSTRAINT "transfer_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "transfer_items_quantity_sent_check" CHECK ((quantity_sent > 0))
);

ALTER TABLE "public"."transfer_items"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."transfer_items" FROM "anon";

CREATE TABLE "public"."user_permissions" (
  "user_id"       uuid                     NOT NULL,
  "permission_id" uuid                     NOT NULL,
  "effect"        text                     NOT NULL,
  "reason"        text                     NOT NULL,
  "assigned_by"   uuid,
  "assigned_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"    timestamp with time zone,
  CONSTRAINT "user_permissions_check" CHECK (((expires_at IS NULL) OR (expires_at > assigned_at))),
  CONSTRAINT "user_permissions_effect_check" CHECK ((effect = ANY (ARRAY['allow'::text, 'deny'::text]))),
  CONSTRAINT "user_permissions_pkey" PRIMARY KEY (user_id, permission_id)
);

ALTER TABLE "public"."user_permissions"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."user_permissions" FROM "anon";

CREATE TABLE "public"."user_roles" (
  "user_id"     uuid                     NOT NULL,
  "role_id"     uuid                     NOT NULL,
  "assigned_at" timestamp with time zone NOT NULL DEFAULT now(),
  "assigned_by" uuid,
  "expires_at"  timestamp with time zone,
  CONSTRAINT "user_roles_check" CHECK (((expires_at IS NULL) OR (expires_at > assigned_at))),
  CONSTRAINT "user_roles_pkey" PRIMARY KEY (user_id, role_id)
);

ALTER TABLE "public"."user_roles"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."user_roles" FROM "anon";

CREATE OR REPLACE FUNCTION private.has_permission (
  p_permission_code text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from public.app_users u
    where u.id = (select auth.uid()) and u.status = 'active'
      and (
        exists (
          select 1 from public.user_roles ur
          join public.role_permissions rp on rp.role_id = ur.role_id
          join public.permissions p on p.id = rp.permission_id
          where ur.user_id = u.id and (ur.expires_at is null or ur.expires_at > now()) and p.code = p_permission_code
        )
        or exists (
          select 1 from public.user_permissions up
          join public.permissions p on p.id = up.permission_id
          where up.user_id = u.id and up.effect = 'allow'
            and (up.expires_at is null or up.expires_at > now()) and p.code = p_permission_code
        )
      )
      and not exists (
        select 1 from public.user_permissions up
        join public.permissions p on p.id = up.permission_id
        where up.user_id = u.id and up.effect = 'deny'
          and (up.expires_at is null or up.expires_at > now()) and p.code = p_permission_code
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.is_active_user()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (select 1 from public.app_users u where u.id = (select auth.uid()) and u.status = 'active');
$function$;

CREATE OR REPLACE FUNCTION private.set_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin new.updated_at := now(); return new; end;
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
  RETURNS event_trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'pg_catalog'
  AS $function$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM PUBLIC, "anon", "authenticated";

ALTER TABLE "public"."app_users"
  ADD CONSTRAINT "app_users_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."app_users"
  ADD CONSTRAINT "app_users_deactivated_by_fkey" FOREIGN KEY (deactivated_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."audit_logs"
  ADD CONSTRAINT "audit_logs_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."church_plants"
  ADD CONSTRAINT "church_plants_community_id_fkey" FOREIGN KEY (community_id) REFERENCES public.communities(id) ON DELETE RESTRICT;

ALTER TABLE "public"."disbursement_confirmations"
  ADD CONSTRAINT "disbursement_confirmations_confirmed_by_fkey" FOREIGN KEY (confirmed_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."disbursement_receipts"
  ADD CONSTRAINT "disbursement_receipts_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."disbursements"
  ADD CONSTRAINT "disbursements_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."disbursement_confirmations"
  ADD CONSTRAINT "disbursement_confirmations_disbursement_id_fkey" FOREIGN KEY (disbursement_id) REFERENCES public.disbursements(id) ON DELETE RESTRICT;

ALTER TABLE "public"."disbursement_receipts"
  ADD CONSTRAINT "disbursement_receipts_disbursement_id_fkey" FOREIGN KEY (disbursement_id) REFERENCES public.disbursements(id) ON DELETE RESTRICT;

ALTER TABLE "public"."communities"
  ADD CONSTRAINT "communities_district_id_fkey" FOREIGN KEY (district_id) REFERENCES public.districts(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expense_receipts"
  ADD CONSTRAINT "expense_receipts_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expense_reviews"
  ADD CONSTRAINT "expense_reviews_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expenses"
  ADD CONSTRAINT "expenses_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expenses"
  ADD CONSTRAINT "expenses_expense_category_id_fkey" FOREIGN KEY (expense_category_id) REFERENCES public.expense_categories(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expense_receipts"
  ADD CONSTRAINT "expense_receipts_expense_id_fkey" FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expense_reviews"
  ADD CONSTRAINT "expense_reviews_expense_id_fkey" FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE RESTRICT;

ALTER TABLE "public"."disbursement_receipts"
  ADD CONSTRAINT "disbursement_receipts_file_asset_id_fkey" FOREIGN KEY (file_asset_id) REFERENCES public.file_assets(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expense_receipts"
  ADD CONSTRAINT "expense_receipts_file_asset_id_fkey" FOREIGN KEY (file_asset_id) REFERENCES public.file_assets(id) ON DELETE RESTRICT;

ALTER TABLE "public"."file_assets"
  ADD CONSTRAINT "file_assets_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."financial_adjustments"
  ADD CONSTRAINT "financial_adjustments_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."financial_adjustments"
  ADD CONSTRAINT "financial_adjustments_disbursement_id_fkey" FOREIGN KEY (disbursement_id) REFERENCES public.disbursements(id) ON DELETE RESTRICT;

ALTER TABLE "public"."financial_adjustments"
  ADD CONSTRAINT "financial_adjustments_expense_id_fkey" FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE RESTRICT;

ALTER TABLE "public"."financial_adjustments"
  ADD CONSTRAINT "financial_adjustments_requested_by_fkey" FOREIGN KEY (requested_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."financial_adjustments"
  ADD CONSTRAINT "financial_adjustments_reversal_of_id_fkey" FOREIGN KEY (reversal_of_id) REFERENCES public.financial_adjustments(id) ON DELETE RESTRICT;

ALTER TABLE "public"."generated_reports"
  ADD CONSTRAINT "generated_reports_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."generated_reports"
  ADD CONSTRAINT "generated_reports_file_asset_id_fkey" FOREIGN KEY (file_asset_id) REFERENCES public.file_assets(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_adjustments"
  ADD CONSTRAINT "inventory_adjustments_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_adjustments"
  ADD CONSTRAINT "inventory_adjustments_requested_by_fkey" FOREIGN KEY (requested_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_assets"
  ADD CONSTRAINT "inventory_assets_inventory_item_id_fkey" FOREIGN KEY (inventory_item_id) REFERENCES public.inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_batches"
  ADD CONSTRAINT "inventory_batches_inventory_item_id_fkey" FOREIGN KEY (inventory_item_id) REFERENCES public.inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_headers"
  ADD CONSTRAINT "inventory_transaction_headers_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_headers"
  ADD CONSTRAINT "inventory_transaction_headers_destination_location_id_fkey" FOREIGN KEY (destination_location_id) REFERENCES public.inventory_locations(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_adjustments"
  ADD CONSTRAINT "inventory_adjustments_transaction_header_id_fkey" FOREIGN KEY (transaction_header_id) REFERENCES public.inventory_transaction_headers(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_headers"
  ADD CONSTRAINT "inventory_transaction_headers_reversal_of_id_fkey" FOREIGN KEY (reversal_of_id) REFERENCES public.inventory_transaction_headers(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_headers"
  ADD CONSTRAINT "inventory_transaction_headers_source_location_id_fkey" FOREIGN KEY (source_location_id) REFERENCES public.inventory_locations(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_lines"
  ADD CONSTRAINT "inventory_transaction_lines_batch_id_fkey" FOREIGN KEY (batch_id) REFERENCES public.inventory_batches(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_lines"
  ADD CONSTRAINT "inventory_transaction_lines_inventory_asset_id_fkey" FOREIGN KEY (inventory_asset_id) REFERENCES public.inventory_assets(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_lines"
  ADD CONSTRAINT "inventory_transaction_lines_inventory_item_id_fkey" FOREIGN KEY (inventory_item_id) REFERENCES public.inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_lines"
  ADD CONSTRAINT "inventory_transaction_lines_transaction_header_id_fkey" FOREIGN KEY (transaction_header_id) REFERENCES public.inventory_transaction_headers(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transfers"
  ADD CONSTRAINT "inventory_transfers_destination_location_id_fkey" FOREIGN KEY (destination_location_id) REFERENCES public.inventory_locations(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transfers"
  ADD CONSTRAINT "inventory_transfers_initiated_by_fkey" FOREIGN KEY (initiated_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_headers"
  ADD CONSTRAINT "inventory_transaction_headers_transfer_id_fkey" FOREIGN KEY (transfer_id) REFERENCES public.inventory_transfers(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transfers"
  ADD CONSTRAINT "inventory_transfers_recipient_user_id_fkey" FOREIGN KEY (recipient_user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transfers"
  ADD CONSTRAINT "inventory_transfers_source_location_id_fkey" FOREIGN KEY (source_location_id) REFERENCES public.inventory_locations(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_batches"
  ADD CONSTRAINT "inventory_batches_language_id_fkey" FOREIGN KEY (language_id) REFERENCES public.languages(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_lines"
  ADD CONSTRAINT "inventory_transaction_lines_language_id_fkey" FOREIGN KEY (language_id) REFERENCES public.languages(id) ON DELETE RESTRICT;

ALTER TABLE "public"."missionaries"
  ADD CONSTRAINT "missionaries_app_user_id_fkey" FOREIGN KEY (app_user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."missionaries"
  ADD CONSTRAINT "missionaries_district_id_fkey" FOREIGN KEY (district_id) REFERENCES public.districts(id) ON DELETE RESTRICT;

ALTER TABLE "public"."church_plants"
  ADD CONSTRAINT "church_plants_missionary_id_fkey" FOREIGN KEY (missionary_id) REFERENCES public.missionaries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."disbursements"
  ADD CONSTRAINT "disbursements_missionary_id_fkey" FOREIGN KEY (missionary_id) REFERENCES public.missionaries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expenses"
  ADD CONSTRAINT "expenses_missionary_id_fkey" FOREIGN KEY (missionary_id) REFERENCES public.missionaries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."financial_adjustments"
  ADD CONSTRAINT "financial_adjustments_missionary_id_fkey" FOREIGN KEY (missionary_id) REFERENCES public.missionaries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_locations"
  ADD CONSTRAINT "inventory_locations_missionary_id_fkey" FOREIGN KEY (missionary_id) REFERENCES public.missionaries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."notifications"
  ADD CONSTRAINT "notifications_recipient_user_id_fkey" FOREIGN KEY (recipient_user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."opening_balance_lines"
  ADD CONSTRAINT "opening_balance_lines_batch_id_fkey" FOREIGN KEY (batch_id) REFERENCES public.inventory_batches(id) ON DELETE RESTRICT;

ALTER TABLE "public"."opening_balance_lines"
  ADD CONSTRAINT "opening_balance_lines_inventory_asset_id_fkey" FOREIGN KEY (inventory_asset_id) REFERENCES public.inventory_assets(id) ON DELETE RESTRICT;

ALTER TABLE "public"."opening_balance_lines"
  ADD CONSTRAINT "opening_balance_lines_inventory_item_id_fkey" FOREIGN KEY (inventory_item_id) REFERENCES public.inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE "public"."opening_balance_lines"
  ADD CONSTRAINT "opening_balance_lines_language_id_fkey" FOREIGN KEY (language_id) REFERENCES public.languages(id) ON DELETE RESTRICT;

ALTER TABLE "public"."opening_balance_lines"
  ADD CONSTRAINT "opening_balance_lines_location_id_fkey" FOREIGN KEY (location_id) REFERENCES public.inventory_locations(id) ON DELETE RESTRICT;

ALTER TABLE "public"."opening_balances"
  ADD CONSTRAINT "opening_balances_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."inventory_transaction_headers"
  ADD CONSTRAINT "inventory_transaction_headers_opening_balance_id_fkey" FOREIGN KEY (opening_balance_id) REFERENCES public.opening_balances(id) ON DELETE RESTRICT;

ALTER TABLE "public"."opening_balance_lines"
  ADD CONSTRAINT "opening_balance_lines_opening_balance_id_fkey" FOREIGN KEY (opening_balance_id) REFERENCES public.opening_balances(id) ON DELETE RESTRICT;

ALTER TABLE "public"."opening_balances"
  ADD CONSTRAINT "opening_balances_verified_by_fkey" FOREIGN KEY (verified_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreach_photos"
  ADD CONSTRAINT "outreach_photos_file_asset_id_fkey" FOREIGN KEY (file_asset_id) REFERENCES public.file_assets(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreach_photos"
  ADD CONSTRAINT "outreach_photos_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreach_reviews"
  ADD CONSTRAINT "outreach_reviews_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreaches"
  ADD CONSTRAINT "outreaches_community_id_fkey" FOREIGN KEY (community_id) REFERENCES public.communities(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreaches"
  ADD CONSTRAINT "outreaches_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreaches"
  ADD CONSTRAINT "outreaches_missionary_id_fkey" FOREIGN KEY (missionary_id) REFERENCES public.missionaries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."church_plants"
  ADD CONSTRAINT "church_plants_outreach_id_fkey" FOREIGN KEY (outreach_id) REFERENCES public.outreaches(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreach_photos"
  ADD CONSTRAINT "outreach_photos_outreach_id_fkey" FOREIGN KEY (outreach_id) REFERENCES public.outreaches(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreach_reviews"
  ADD CONSTRAINT "outreach_reviews_outreach_id_fkey" FOREIGN KEY (outreach_id) REFERENCES public.outreaches(id) ON DELETE RESTRICT;

ALTER TABLE "public"."church_plants"
  ADD CONSTRAINT "church_plants_partner_ministry_id_fkey" FOREIGN KEY (partner_ministry_id) REFERENCES public.partner_ministries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreaches"
  ADD CONSTRAINT "outreaches_partner_ministry_id_fkey" FOREIGN KEY (partner_ministry_id) REFERENCES public.partner_ministries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."outreaches"
  ADD CONSTRAINT "outreaches_people_group_id_fkey" FOREIGN KEY (people_group_id) REFERENCES public.people_groups(id) ON DELETE RESTRICT;

ALTER TABLE "public"."report_approvals"
  ADD CONSTRAINT "report_approvals_generated_report_id_fkey" FOREIGN KEY (generated_report_id) REFERENCES public.generated_reports(id) ON DELETE RESTRICT;

ALTER TABLE "public"."report_approvals"
  ADD CONSTRAINT "report_approvals_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."disbursements"
  ADD CONSTRAINT "disbursements_reporting_period_id_fkey" FOREIGN KEY (reporting_period_id) REFERENCES public.reporting_periods(id) ON DELETE RESTRICT;

ALTER TABLE "public"."expenses"
  ADD CONSTRAINT "expenses_reporting_period_id_fkey" FOREIGN KEY (reporting_period_id) REFERENCES public.reporting_periods(id) ON DELETE RESTRICT;

ALTER TABLE "public"."financial_adjustments"
  ADD CONSTRAINT "financial_adjustments_reporting_period_id_fkey" FOREIGN KEY (reporting_period_id) REFERENCES public.reporting_periods(id) ON DELETE RESTRICT;

ALTER TABLE "public"."generated_reports"
  ADD CONSTRAINT "generated_reports_reporting_period_id_fkey" FOREIGN KEY (reporting_period_id) REFERENCES public.reporting_periods(id) ON DELETE RESTRICT;

ALTER TABLE "public"."role_permissions"
  ADD CONSTRAINT "role_permissions_assigned_by_fkey" FOREIGN KEY (assigned_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."role_permissions"
  ADD CONSTRAINT "role_permissions_permission_id_fkey" FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE RESTRICT;

ALTER TABLE "public"."role_permissions"
  ADD CONSTRAINT "role_permissions_role_id_fkey" FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE RESTRICT;

ALTER TABLE "public"."sync_records"
  ADD CONSTRAINT "sync_records_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."system_settings"
  ADD CONSTRAINT "system_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimonies"
  ADD CONSTRAINT "testimonies_community_id_fkey" FOREIGN KEY (community_id) REFERENCES public.communities(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimonies"
  ADD CONSTRAINT "testimonies_consent_recorded_by_fkey" FOREIGN KEY (consent_recorded_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimonies"
  ADD CONSTRAINT "testimonies_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimonies"
  ADD CONSTRAINT "testimonies_missionary_id_fkey" FOREIGN KEY (missionary_id) REFERENCES public.missionaries(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimonies"
  ADD CONSTRAINT "testimonies_outreach_id_fkey" FOREIGN KEY (outreach_id) REFERENCES public.outreaches(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimony_media"
  ADD CONSTRAINT "testimony_media_file_asset_id_fkey" FOREIGN KEY (file_asset_id) REFERENCES public.file_assets(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimony_media"
  ADD CONSTRAINT "testimony_media_testimony_id_fkey" FOREIGN KEY (testimony_id) REFERENCES public.testimonies(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimony_reviews"
  ADD CONSTRAINT "testimony_reviews_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."testimony_reviews"
  ADD CONSTRAINT "testimony_reviews_testimony_id_fkey" FOREIGN KEY (testimony_id) REFERENCES public.testimonies(id) ON DELETE RESTRICT;

ALTER TABLE "public"."transfer_confirmations"
  ADD CONSTRAINT "transfer_confirmations_confirmed_by_fkey" FOREIGN KEY (confirmed_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."transfer_confirmations"
  ADD CONSTRAINT "transfer_confirmations_transfer_id_fkey" FOREIGN KEY (transfer_id) REFERENCES public.inventory_transfers(id) ON DELETE RESTRICT;

ALTER TABLE "public"."transfer_items"
  ADD CONSTRAINT "transfer_items_batch_id_fkey" FOREIGN KEY (batch_id) REFERENCES public.inventory_batches(id) ON DELETE RESTRICT;

ALTER TABLE "public"."transfer_items"
  ADD CONSTRAINT "transfer_items_inventory_asset_id_fkey" FOREIGN KEY (inventory_asset_id) REFERENCES public.inventory_assets(id) ON DELETE RESTRICT;

ALTER TABLE "public"."transfer_items"
  ADD CONSTRAINT "transfer_items_inventory_item_id_fkey" FOREIGN KEY (inventory_item_id) REFERENCES public.inventory_items(id) ON DELETE RESTRICT;

ALTER TABLE "public"."transfer_items"
  ADD CONSTRAINT "transfer_items_language_id_fkey" FOREIGN KEY (language_id) REFERENCES public.languages(id) ON DELETE RESTRICT;

ALTER TABLE "public"."transfer_items"
  ADD CONSTRAINT "transfer_items_transfer_id_fkey" FOREIGN KEY (transfer_id) REFERENCES public.inventory_transfers(id) ON DELETE RESTRICT;

ALTER TABLE "public"."user_permissions"
  ADD CONSTRAINT "user_permissions_assigned_by_fkey" FOREIGN KEY (assigned_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."user_permissions"
  ADD CONSTRAINT "user_permissions_permission_id_fkey" FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE RESTRICT;

ALTER TABLE "public"."user_permissions"
  ADD CONSTRAINT "user_permissions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."user_roles"
  ADD CONSTRAINT "user_roles_assigned_by_fkey" FOREIGN KEY (assigned_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE "public"."user_roles"
  ADD CONSTRAINT "user_roles_role_id_fkey" FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE RESTRICT;

ALTER TABLE "public"."user_roles"
  ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT;

CREATE INDEX app_users_status_idx ON public.app_users USING btree (status);

CREATE INDEX audit_logs_entity_idx ON public.audit_logs USING btree (entity_type, entity_id, created_at DESC);

CREATE INDEX communities_district_idx ON public.communities USING btree (district_id);

CREATE INDEX disbursements_missionary_period_idx ON public.disbursements USING btree (missionary_id, reporting_period_id);

CREATE INDEX expense_reviews_expense_created_idx ON public.expense_reviews USING btree (expense_id, created_at DESC);

CREATE INDEX expenses_missionary_period_status_idx ON public.expenses USING btree (missionary_id, reporting_period_id, status);

CREATE INDEX idx_fk_app_users_deactivated_by_fkey_7c26e0238d ON public.app_users USING btree (deactivated_by);

CREATE INDEX idx_fk_audit_logs_actor_user_id_fkey_cd0a261eea ON public.audit_logs USING btree (actor_user_id);

CREATE INDEX idx_fk_church_plants_community_id_fkey_610b31f2ad ON public.church_plants USING btree (community_id);

CREATE INDEX idx_fk_church_plants_missionary_id_fkey_df89238cde ON public.church_plants USING btree (missionary_id);

CREATE INDEX idx_fk_church_plants_outreach_id_fkey_7c8b4080c9 ON public.church_plants USING btree (outreach_id);

CREATE INDEX idx_fk_church_plants_partner_ministry_id_fkey_edeef07a25 ON public.church_plants USING btree (partner_ministry_id);

CREATE INDEX idx_fk_disbursement_confirmations_confirmed_by_f_7127a0ad59 ON public.disbursement_confirmations USING btree (confirmed_by);

CREATE INDEX idx_fk_disbursement_confirmations_disbursement_i_e163016754 ON public.disbursement_confirmations USING btree (disbursement_id);

CREATE INDEX idx_fk_disbursement_receipts_file_asset_id_fkey_ca1d6feb95 ON public.disbursement_receipts USING btree (file_asset_id);

CREATE INDEX idx_fk_disbursement_receipts_uploaded_by_fkey_1eed786d7e ON public.disbursement_receipts USING btree (uploaded_by);

CREATE INDEX idx_fk_disbursements_created_by_fkey_024daf4d4a ON public.disbursements USING btree (created_by);

CREATE INDEX idx_fk_disbursements_reporting_period_id_fkey_d2b5e625fb ON public.disbursements USING btree (reporting_period_id);

CREATE INDEX idx_fk_expense_receipts_file_asset_id_fkey_7ec13a1728 ON public.expense_receipts USING btree (file_asset_id);

CREATE INDEX idx_fk_expense_receipts_uploaded_by_fkey_4bdc2a5999 ON public.expense_receipts USING btree (uploaded_by);

CREATE INDEX idx_fk_expense_reviews_reviewer_id_fkey_947fbdda80 ON public.expense_reviews USING btree (reviewer_id);

CREATE INDEX idx_fk_expenses_created_by_fkey_89c2921d39 ON public.expenses USING btree (created_by);

CREATE INDEX idx_fk_expenses_expense_category_id_fkey_d4b7741888 ON public.expenses USING btree (expense_category_id);

CREATE INDEX idx_fk_expenses_reporting_period_id_fkey_5a348e08dc ON public.expenses USING btree (reporting_period_id);

CREATE INDEX idx_fk_file_assets_uploaded_by_fkey_3458babbf6 ON public.file_assets USING btree (uploaded_by);

CREATE INDEX idx_fk_financial_adjustments_approved_by_fkey_e42267de5f ON public.financial_adjustments USING btree (approved_by);

CREATE INDEX idx_fk_financial_adjustments_disbursement_id_fke_89fbc51ab0 ON public.financial_adjustments USING btree (disbursement_id);

CREATE INDEX idx_fk_financial_adjustments_expense_id_fkey_2fd0e0b527 ON public.financial_adjustments USING btree (expense_id);

CREATE INDEX idx_fk_financial_adjustments_missionary_id_fkey_b9fe408df6 ON public.financial_adjustments USING btree (missionary_id);

CREATE INDEX idx_fk_financial_adjustments_reporting_period_id_e4eec0bef7 ON public.financial_adjustments USING btree (reporting_period_id);

CREATE INDEX idx_fk_financial_adjustments_requested_by_fkey_f5a605afeb ON public.financial_adjustments USING btree (requested_by);

CREATE INDEX idx_fk_financial_adjustments_reversal_of_id_fkey_b8ab3457fb ON public.financial_adjustments USING btree (reversal_of_id);

CREATE INDEX idx_fk_generated_reports_created_by_fkey_a0465cd0f2 ON public.generated_reports USING btree (created_by);

CREATE INDEX idx_fk_generated_reports_file_asset_id_fkey_fc1775bb13 ON public.generated_reports USING btree (file_asset_id);

CREATE INDEX idx_fk_generated_reports_reporting_period_id_fke_d12b08cfd3 ON public.generated_reports USING btree (reporting_period_id);

CREATE INDEX idx_fk_inventory_adjustments_approved_by_fkey_38fa7cc084 ON public.inventory_adjustments USING btree (approved_by);

CREATE INDEX idx_fk_inventory_adjustments_requested_by_fkey_93ab91df6e ON public.inventory_adjustments USING btree (requested_by);

CREATE INDEX idx_fk_inventory_assets_inventory_item_id_fkey_f67885b700 ON public.inventory_assets USING btree (inventory_item_id);

CREATE INDEX idx_fk_inventory_batches_language_id_fkey_aabffadc1f ON public.inventory_batches USING btree (language_id);

CREATE INDEX idx_fk_inventory_transaction_headers_created_by__b6b67e6fc1 ON public.inventory_transaction_headers USING btree (created_by);

CREATE INDEX idx_fk_inventory_transaction_headers_destination_a12b0c64fe ON public.inventory_transaction_headers USING btree (destination_location_id);

CREATE INDEX idx_fk_inventory_transaction_headers_opening_bal_c3bb3616cb ON public.inventory_transaction_headers USING btree (opening_balance_id);

CREATE INDEX idx_fk_inventory_transaction_headers_reversal_of_eaac1813a2 ON public.inventory_transaction_headers USING btree (reversal_of_id);

CREATE INDEX idx_fk_inventory_transaction_headers_source_loca_38021513bc ON public.inventory_transaction_headers USING btree (source_location_id);

CREATE INDEX idx_fk_inventory_transaction_headers_transfer_id_b112d271cc ON public.inventory_transaction_headers USING btree (transfer_id);

CREATE INDEX idx_fk_inventory_transaction_lines_batch_id_fkey_7c449fb6c2 ON public.inventory_transaction_lines USING btree (batch_id);

CREATE INDEX idx_fk_inventory_transaction_lines_inventory_ass_43f1d4fd29 ON public.inventory_transaction_lines USING btree (inventory_asset_id);

CREATE INDEX idx_fk_inventory_transaction_lines_language_id_f_7c9ff51322 ON public.inventory_transaction_lines USING btree (language_id);

CREATE INDEX idx_fk_inventory_transaction_lines_transaction_h_ef6ccea172 ON public.inventory_transaction_lines USING btree (transaction_header_id);

CREATE INDEX idx_fk_inventory_transfers_destination_location__8abd7c521a ON public.inventory_transfers USING btree (destination_location_id);

CREATE INDEX idx_fk_inventory_transfers_recipient_user_id_fke_59eeda55d2 ON public.inventory_transfers USING btree (recipient_user_id);

CREATE INDEX idx_fk_inventory_transfers_source_location_id_fk_d59f2313ec ON public.inventory_transfers USING btree (source_location_id);

CREATE INDEX idx_fk_notifications_recipient_user_id_fkey_f19e963811 ON public.notifications USING btree (recipient_user_id);

CREATE INDEX idx_fk_opening_balance_lines_batch_id_fkey_1dcc91a01b ON public.opening_balance_lines USING btree (batch_id);

CREATE INDEX idx_fk_opening_balance_lines_inventory_asset_id__26242e31fc ON public.opening_balance_lines USING btree (inventory_asset_id);

CREATE INDEX idx_fk_opening_balance_lines_inventory_item_id_f_6ce90b138a ON public.opening_balance_lines USING btree (inventory_item_id);

CREATE INDEX idx_fk_opening_balance_lines_language_id_fkey_8eb1157d7a ON public.opening_balance_lines USING btree (language_id);

CREATE INDEX idx_fk_opening_balance_lines_location_id_fkey_ce142f66a9 ON public.opening_balance_lines USING btree (location_id);

CREATE INDEX idx_fk_opening_balance_lines_opening_balance_id__67769ca5f9 ON public.opening_balance_lines USING btree (opening_balance_id);

CREATE INDEX idx_fk_opening_balances_created_by_fkey_6ea82c8cc1 ON public.opening_balances USING btree (created_by);

CREATE INDEX idx_fk_opening_balances_verified_by_fkey_9019c62fb2 ON public.opening_balances USING btree (verified_by);

CREATE INDEX idx_fk_outreach_photos_file_asset_id_fkey_05fe504ac1 ON public.outreach_photos USING btree (file_asset_id);

CREATE INDEX idx_fk_outreach_photos_uploaded_by_fkey_e9ac404432 ON public.outreach_photos USING btree (uploaded_by);

CREATE INDEX idx_fk_outreach_reviews_outreach_id_fkey_027f83c6dd ON public.outreach_reviews USING btree (outreach_id);

CREATE INDEX idx_fk_outreach_reviews_reviewer_id_fkey_fd554d0c57 ON public.outreach_reviews USING btree (reviewer_id);

CREATE INDEX idx_fk_outreaches_created_by_fkey_704e31b47e ON public.outreaches USING btree (created_by);

CREATE INDEX idx_fk_outreaches_partner_ministry_id_fkey_799ee11825 ON public.outreaches USING btree (partner_ministry_id);

CREATE INDEX idx_fk_outreaches_people_group_id_fkey_ebfa4f760b ON public.outreaches USING btree (people_group_id);

CREATE INDEX idx_fk_report_approvals_generated_report_id_fkey_f4c73d4f08 ON public.report_approvals USING btree (generated_report_id);

CREATE INDEX idx_fk_report_approvals_reviewer_id_fkey_3b8b72b7d2 ON public.report_approvals USING btree (reviewer_id);

CREATE INDEX idx_fk_role_permissions_assigned_by_fkey_6ec7c450b6 ON public.role_permissions USING btree (assigned_by);

CREATE INDEX idx_fk_role_permissions_permission_id_fkey_7557ca12b2 ON public.role_permissions USING btree (permission_id);

CREATE INDEX idx_fk_system_settings_updated_by_fkey_54faac5366 ON public.system_settings USING btree (updated_by);

CREATE INDEX idx_fk_testimonies_community_id_fkey_becfa78185 ON public.testimonies USING btree (community_id);

CREATE INDEX idx_fk_testimonies_consent_recorded_by_fkey_3b4117f281 ON public.testimonies USING btree (consent_recorded_by);

CREATE INDEX idx_fk_testimonies_created_by_fkey_ad4b2cb2cd ON public.testimonies USING btree (created_by);

CREATE INDEX idx_fk_testimonies_outreach_id_fkey_580fe4e5e5 ON public.testimonies USING btree (outreach_id);

CREATE INDEX idx_fk_testimony_media_file_asset_id_fkey_f349bf1a35 ON public.testimony_media USING btree (file_asset_id);

CREATE INDEX idx_fk_testimony_reviews_reviewer_id_fkey_23ac89610b ON public.testimony_reviews USING btree (reviewer_id);

CREATE INDEX idx_fk_testimony_reviews_testimony_id_fkey_0e82b2476f ON public.testimony_reviews USING btree (testimony_id);

CREATE INDEX idx_fk_transfer_confirmations_confirmed_by_fkey_01d45c55e0 ON public.transfer_confirmations USING btree (confirmed_by);

CREATE INDEX idx_fk_transfer_confirmations_transfer_id_fkey_7b018099f4 ON public.transfer_confirmations USING btree (transfer_id);

CREATE INDEX idx_fk_transfer_items_batch_id_fkey_c54112b999 ON public.transfer_items USING btree (batch_id);

CREATE INDEX idx_fk_transfer_items_inventory_asset_id_fkey_eb08d957ba ON public.transfer_items USING btree (inventory_asset_id);

CREATE INDEX idx_fk_transfer_items_inventory_item_id_fkey_e04bdbafc0 ON public.transfer_items USING btree (inventory_item_id);

CREATE INDEX idx_fk_transfer_items_language_id_fkey_ca23f9b5e5 ON public.transfer_items USING btree (language_id);

CREATE INDEX idx_fk_transfer_items_transfer_id_fkey_e2bf06b0af ON public.transfer_items USING btree (transfer_id);

CREATE INDEX idx_fk_user_permissions_assigned_by_fkey_300f9906fa ON public.user_permissions USING btree (assigned_by);

CREATE INDEX idx_fk_user_permissions_permission_id_fkey_0b77d1c736 ON public.user_permissions USING btree (permission_id);

CREATE INDEX idx_fk_user_roles_assigned_by_fkey_93b97e8cfa ON public.user_roles USING btree (assigned_by);

CREATE INDEX idx_fk_user_roles_role_id_fkey_289ea8ecf3 ON public.user_roles USING btree (role_id);

CREATE INDEX inventory_transfers_status_created_idx ON public.inventory_transfers USING btree (status, created_at DESC);

CREATE INDEX inventory_tx_effective_idx ON public.inventory_transaction_headers USING btree (effective_at DESC);

CREATE INDEX inventory_tx_lines_item_idx ON public.inventory_transaction_lines USING btree (inventory_item_id, language_id);

CREATE INDEX missionaries_district_idx ON public.missionaries USING btree (district_id);

CREATE INDEX notifications_user_unread_idx ON public.notifications USING btree (recipient_user_id, created_at DESC)
  WHERE (read_at IS NULL);

CREATE INDEX outreaches_community_date_idx ON public.outreaches USING btree (community_id, outreach_date DESC);

CREATE INDEX outreaches_missionary_date_idx ON public.outreaches USING btree (missionary_id, outreach_date DESC);

CREATE INDEX sync_records_user_status_idx ON public.sync_records USING btree (user_id, status, received_at);

CREATE INDEX testimonies_status_created_idx ON public.testimonies USING btree (status, created_at DESC);

CREATE TRIGGER app_users_set_updated_at
  BEFORE UPDATE ON public.app_users
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER church_plants_set_updated_at
  BEFORE UPDATE ON public.church_plants
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER communities_set_updated_at
  BEFORE UPDATE ON public.communities
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER disbursements_set_updated_at
  BEFORE UPDATE ON public.disbursements
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER districts_set_updated_at
  BEFORE UPDATE ON public.districts
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER expense_categories_set_updated_at
  BEFORE UPDATE ON public.expense_categories
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER expenses_set_updated_at
  BEFORE UPDATE ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER inventory_items_set_updated_at
  BEFORE UPDATE ON public.inventory_items
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER inventory_transfers_set_updated_at
  BEFORE UPDATE ON public.inventory_transfers
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER languages_set_updated_at
  BEFORE UPDATE ON public.languages
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER missionaries_set_updated_at
  BEFORE UPDATE ON public.missionaries
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER outreaches_set_updated_at
  BEFORE UPDATE ON public.outreaches
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER partner_ministries_set_updated_at
  BEFORE UPDATE ON public.partner_ministries
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER people_groups_set_updated_at
  BEFORE UPDATE ON public.people_groups
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER system_settings_set_updated_at
  BEFORE UPDATE ON public.system_settings
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER testimonies_set_updated_at
  BEFORE UPDATE ON public.testimonies
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();

CREATE POLICY "app_users_read_self_or_admin" ON "public"."app_users"
  FOR SELECT
  TO "authenticated"
  USING (((id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_permission('users.manage'::text) AS has_permission)));

CREATE POLICY "communities_read_active" ON "public"."communities"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "districts_read_active" ON "public"."districts"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "expense_categories_read_active" ON "public"."expense_categories"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "inventory_items_read_active" ON "public"."inventory_items"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "inventory_locations_read_active" ON "public"."inventory_locations"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "languages_read_active" ON "public"."languages"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "missionaries_read_self_or_authorized" ON "public"."missionaries"
  FOR SELECT
  TO "authenticated"
  USING (((app_user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_permission('missionaries.read_all'::text) AS has_permission)));

CREATE POLICY "partner_ministries_read_active" ON "public"."partner_ministries"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "people_groups_read_active" ON "public"."people_groups"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "permissions_read_active" ON "public"."permissions"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "reporting_periods_read_active" ON "public"."reporting_periods"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "role_permissions_read_active" ON "public"."role_permissions"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "roles_read_active" ON "public"."roles"
  FOR SELECT
  TO "authenticated"
  USING (( SELECT private.is_active_user() AS is_active_user));

CREATE POLICY "user_permissions_read_self_or_admin" ON "public"."user_permissions"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_permission('users.manage'::text) AS has_permission)));

CREATE POLICY "user_roles_read_self_or_admin" ON "public"."user_roles"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_permission('users.manage'::text) AS has_permission)));

CREATE EVENT TRIGGER "ensure_rls"
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION "public"."rls_auto_enable"();

REVOKE ALL ON FUNCTION "private"."has_permission"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."has_permission"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "private"."is_active_user"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "private"."is_active_user"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."rls_auto_enable"() TO "service_role";

GRANT USAGE ON SCHEMA "private" TO "authenticated";

REVOKE ALL ON TABLE "public"."app_users" FROM "authenticated";

GRANT SELECT ON TABLE "public"."app_users" TO "authenticated";

REVOKE ALL ON TABLE "public"."app_users" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."app_users" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."app_users" TO "service_role";

REVOKE ALL ON TABLE "public"."audit_logs" FROM "authenticated";

GRANT SELECT ON TABLE "public"."audit_logs" TO "authenticated";

REVOKE ALL ON TABLE "public"."audit_logs" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."audit_logs" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."audit_logs" TO "service_role";

REVOKE ALL ON TABLE "public"."church_plants" FROM "authenticated";

GRANT SELECT ON TABLE "public"."church_plants" TO "authenticated";

REVOKE ALL ON TABLE "public"."church_plants" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."church_plants" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."church_plants" TO "service_role";

REVOKE ALL ON TABLE "public"."communities" FROM "authenticated";

GRANT SELECT ON TABLE "public"."communities" TO "authenticated";

REVOKE ALL ON TABLE "public"."communities" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."communities" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."communities" TO "service_role";

REVOKE ALL ON TABLE "public"."disbursement_confirmations" FROM "authenticated";

GRANT SELECT ON TABLE "public"."disbursement_confirmations" TO "authenticated";

REVOKE ALL ON TABLE "public"."disbursement_confirmations" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."disbursement_confirmations" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."disbursement_confirmations" TO "service_role";

REVOKE ALL ON TABLE "public"."disbursement_receipts" FROM "authenticated";

GRANT SELECT ON TABLE "public"."disbursement_receipts" TO "authenticated";

REVOKE ALL ON TABLE "public"."disbursement_receipts" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."disbursement_receipts" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."disbursement_receipts" TO "service_role";

REVOKE ALL ON TABLE "public"."disbursements" FROM "authenticated";

GRANT SELECT ON TABLE "public"."disbursements" TO "authenticated";

REVOKE ALL ON TABLE "public"."disbursements" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."disbursements" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."disbursements" TO "service_role";

REVOKE ALL ON TABLE "public"."districts" FROM "authenticated";

GRANT SELECT ON TABLE "public"."districts" TO "authenticated";

REVOKE ALL ON TABLE "public"."districts" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."districts" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."districts" TO "service_role";

REVOKE ALL ON TABLE "public"."expense_categories" FROM "authenticated";

GRANT SELECT ON TABLE "public"."expense_categories" TO "authenticated";

REVOKE ALL ON TABLE "public"."expense_categories" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."expense_categories" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."expense_categories" TO "service_role";

REVOKE ALL ON TABLE "public"."expense_receipts" FROM "authenticated";

GRANT SELECT ON TABLE "public"."expense_receipts" TO "authenticated";

REVOKE ALL ON TABLE "public"."expense_receipts" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."expense_receipts" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."expense_receipts" TO "service_role";

REVOKE ALL ON TABLE "public"."expense_reviews" FROM "authenticated";

GRANT SELECT ON TABLE "public"."expense_reviews" TO "authenticated";

REVOKE ALL ON TABLE "public"."expense_reviews" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."expense_reviews" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."expense_reviews" TO "service_role";

REVOKE ALL ON TABLE "public"."expenses" FROM "authenticated";

GRANT SELECT ON TABLE "public"."expenses" TO "authenticated";

REVOKE ALL ON TABLE "public"."expenses" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."expenses" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."expenses" TO "service_role";

REVOKE ALL ON TABLE "public"."file_assets" FROM "authenticated";

GRANT SELECT ON TABLE "public"."file_assets" TO "authenticated";

REVOKE ALL ON TABLE "public"."file_assets" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."file_assets" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."file_assets" TO "service_role";

REVOKE ALL ON TABLE "public"."financial_adjustments" FROM "authenticated";

GRANT SELECT ON TABLE "public"."financial_adjustments" TO "authenticated";

REVOKE ALL ON TABLE "public"."financial_adjustments" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."financial_adjustments" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."financial_adjustments" TO "service_role";

REVOKE ALL ON TABLE "public"."generated_reports" FROM "authenticated";

GRANT SELECT ON TABLE "public"."generated_reports" TO "authenticated";

REVOKE ALL ON TABLE "public"."generated_reports" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."generated_reports" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."generated_reports" TO "service_role";

REVOKE ALL ON TABLE "public"."inventory_adjustments" FROM "authenticated";

GRANT SELECT ON TABLE "public"."inventory_adjustments" TO "authenticated";

REVOKE ALL ON TABLE "public"."inventory_adjustments" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_adjustments" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_adjustments" TO "service_role";

REVOKE ALL ON TABLE "public"."inventory_assets" FROM "authenticated";

GRANT SELECT ON TABLE "public"."inventory_assets" TO "authenticated";

REVOKE ALL ON TABLE "public"."inventory_assets" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_assets" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_assets" TO "service_role";

REVOKE ALL ON TABLE "public"."inventory_batches" FROM "authenticated";

GRANT SELECT ON TABLE "public"."inventory_batches" TO "authenticated";

REVOKE ALL ON TABLE "public"."inventory_batches" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_batches" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_batches" TO "service_role";

REVOKE ALL ON TABLE "public"."inventory_items" FROM "authenticated";

GRANT SELECT ON TABLE "public"."inventory_items" TO "authenticated";

REVOKE ALL ON TABLE "public"."inventory_items" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_items" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_items" TO "service_role";

REVOKE ALL ON TABLE "public"."inventory_locations" FROM "authenticated";

GRANT SELECT ON TABLE "public"."inventory_locations" TO "authenticated";

REVOKE ALL ON TABLE "public"."inventory_locations" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_locations" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_locations" TO "service_role";

REVOKE ALL ON TABLE "public"."inventory_transaction_headers" FROM "authenticated";

GRANT SELECT ON TABLE "public"."inventory_transaction_headers" TO "authenticated";

REVOKE ALL ON TABLE "public"."inventory_transaction_headers" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_transaction_headers" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_transaction_headers" TO "service_role";

REVOKE ALL ON TABLE "public"."inventory_transaction_lines" FROM "authenticated";

GRANT SELECT ON TABLE "public"."inventory_transaction_lines" TO "authenticated";

REVOKE ALL ON TABLE "public"."inventory_transaction_lines" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_transaction_lines" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_transaction_lines" TO "service_role";

REVOKE ALL ON TABLE "public"."inventory_transfers" FROM "authenticated";

GRANT SELECT ON TABLE "public"."inventory_transfers" TO "authenticated";

REVOKE ALL ON TABLE "public"."inventory_transfers" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_transfers" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."inventory_transfers" TO "service_role";

REVOKE ALL ON TABLE "public"."languages" FROM "authenticated";

GRANT SELECT ON TABLE "public"."languages" TO "authenticated";

REVOKE ALL ON TABLE "public"."languages" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."languages" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."languages" TO "service_role";

REVOKE ALL ON TABLE "public"."missionaries" FROM "authenticated";

GRANT SELECT ON TABLE "public"."missionaries" TO "authenticated";

REVOKE ALL ON TABLE "public"."missionaries" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."missionaries" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."missionaries" TO "service_role";

REVOKE ALL ON TABLE "public"."notifications" FROM "authenticated";

GRANT SELECT ON TABLE "public"."notifications" TO "authenticated";

REVOKE ALL ON TABLE "public"."notifications" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."notifications" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."notifications" TO "service_role";

REVOKE ALL ON TABLE "public"."opening_balance_lines" FROM "authenticated";

GRANT SELECT ON TABLE "public"."opening_balance_lines" TO "authenticated";

REVOKE ALL ON TABLE "public"."opening_balance_lines" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."opening_balance_lines" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."opening_balance_lines" TO "service_role";

REVOKE ALL ON TABLE "public"."opening_balances" FROM "authenticated";

GRANT SELECT ON TABLE "public"."opening_balances" TO "authenticated";

REVOKE ALL ON TABLE "public"."opening_balances" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."opening_balances" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."opening_balances" TO "service_role";

REVOKE ALL ON TABLE "public"."outreach_photos" FROM "authenticated";

GRANT SELECT ON TABLE "public"."outreach_photos" TO "authenticated";

REVOKE ALL ON TABLE "public"."outreach_photos" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."outreach_photos" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."outreach_photos" TO "service_role";

REVOKE ALL ON TABLE "public"."outreach_reviews" FROM "authenticated";

GRANT SELECT ON TABLE "public"."outreach_reviews" TO "authenticated";

REVOKE ALL ON TABLE "public"."outreach_reviews" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."outreach_reviews" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."outreach_reviews" TO "service_role";

REVOKE ALL ON TABLE "public"."outreaches" FROM "authenticated";

GRANT SELECT ON TABLE "public"."outreaches" TO "authenticated";

REVOKE ALL ON TABLE "public"."outreaches" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."outreaches" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."outreaches" TO "service_role";

REVOKE ALL ON TABLE "public"."partner_ministries" FROM "authenticated";

GRANT SELECT ON TABLE "public"."partner_ministries" TO "authenticated";

REVOKE ALL ON TABLE "public"."partner_ministries" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."partner_ministries" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."partner_ministries" TO "service_role";

REVOKE ALL ON TABLE "public"."people_groups" FROM "authenticated";

GRANT SELECT ON TABLE "public"."people_groups" TO "authenticated";

REVOKE ALL ON TABLE "public"."people_groups" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."people_groups" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."people_groups" TO "service_role";

REVOKE ALL ON TABLE "public"."permissions" FROM "authenticated";

GRANT SELECT ON TABLE "public"."permissions" TO "authenticated";

REVOKE ALL ON TABLE "public"."permissions" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."permissions" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."permissions" TO "service_role";

REVOKE ALL ON TABLE "public"."report_approvals" FROM "authenticated";

GRANT SELECT ON TABLE "public"."report_approvals" TO "authenticated";

REVOKE ALL ON TABLE "public"."report_approvals" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."report_approvals" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."report_approvals" TO "service_role";

REVOKE ALL ON TABLE "public"."reporting_periods" FROM "authenticated";

GRANT SELECT ON TABLE "public"."reporting_periods" TO "authenticated";

REVOKE ALL ON TABLE "public"."reporting_periods" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."reporting_periods" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."reporting_periods" TO "service_role";

REVOKE ALL ON TABLE "public"."role_permissions" FROM "authenticated";

GRANT SELECT ON TABLE "public"."role_permissions" TO "authenticated";

REVOKE ALL ON TABLE "public"."role_permissions" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."role_permissions" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."role_permissions" TO "service_role";

REVOKE ALL ON TABLE "public"."roles" FROM "authenticated";

GRANT SELECT ON TABLE "public"."roles" TO "authenticated";

REVOKE ALL ON TABLE "public"."roles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."roles" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."roles" TO "service_role";

REVOKE ALL ON TABLE "public"."sync_records" FROM "authenticated";

GRANT SELECT ON TABLE "public"."sync_records" TO "authenticated";

REVOKE ALL ON TABLE "public"."sync_records" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."sync_records" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."sync_records" TO "service_role";

REVOKE ALL ON TABLE "public"."system_settings" FROM "authenticated";

GRANT SELECT ON TABLE "public"."system_settings" TO "authenticated";

REVOKE ALL ON TABLE "public"."system_settings" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."system_settings" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."system_settings" TO "service_role";

REVOKE ALL ON TABLE "public"."testimonies" FROM "authenticated";

GRANT SELECT ON TABLE "public"."testimonies" TO "authenticated";

REVOKE ALL ON TABLE "public"."testimonies" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."testimonies" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."testimonies" TO "service_role";

REVOKE ALL ON TABLE "public"."testimony_media" FROM "authenticated";

GRANT SELECT ON TABLE "public"."testimony_media" TO "authenticated";

REVOKE ALL ON TABLE "public"."testimony_media" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."testimony_media" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."testimony_media" TO "service_role";

REVOKE ALL ON TABLE "public"."testimony_reviews" FROM "authenticated";

GRANT SELECT ON TABLE "public"."testimony_reviews" TO "authenticated";

REVOKE ALL ON TABLE "public"."testimony_reviews" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."testimony_reviews" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."testimony_reviews" TO "service_role";

REVOKE ALL ON TABLE "public"."transfer_confirmations" FROM "authenticated";

GRANT SELECT ON TABLE "public"."transfer_confirmations" TO "authenticated";

REVOKE ALL ON TABLE "public"."transfer_confirmations" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."transfer_confirmations" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."transfer_confirmations" TO "service_role";

REVOKE ALL ON TABLE "public"."transfer_items" FROM "authenticated";

GRANT SELECT ON TABLE "public"."transfer_items" TO "authenticated";

REVOKE ALL ON TABLE "public"."transfer_items" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."transfer_items" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."transfer_items" TO "service_role";

REVOKE ALL ON TABLE "public"."user_permissions" FROM "authenticated";

GRANT SELECT ON TABLE "public"."user_permissions" TO "authenticated";

REVOKE ALL ON TABLE "public"."user_permissions" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_permissions" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_permissions" TO "service_role";

REVOKE ALL ON TABLE "public"."user_roles" FROM "authenticated";

GRANT SELECT ON TABLE "public"."user_roles" TO "authenticated";

REVOKE ALL ON TABLE "public"."user_roles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_roles" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_roles" TO "service_role";

