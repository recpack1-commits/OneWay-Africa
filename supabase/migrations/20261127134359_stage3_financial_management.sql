BEGIN;

-- Stage 3 adds 2027+ financial workflows without seeding transaction data.

ALTER TABLE public.expenses
  ALTER COLUMN expense_category_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS exchange_rate_date date,
  ADD COLUMN IF NOT EXISTS exchange_rate_source text,
  ADD COLUMN IF NOT EXISTS submission_payload jsonb,
  ADD COLUMN IF NOT EXISTS over_funds_flag boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS over_funds_note text;

ALTER TABLE public.disbursements
  ADD COLUMN IF NOT EXISTS exchange_rate_date date,
  ADD COLUMN IF NOT EXISTS exchange_rate_source text,
  ADD COLUMN IF NOT EXISTS effective_amount_received numeric(14,2),
  ADD COLUMN IF NOT EXISTS settlement_note text,
  ADD COLUMN IF NOT EXISTS settled_short_approved_by uuid,
  ADD COLUMN IF NOT EXISTS settled_short_approved_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS client_submission_id uuid,
  ADD COLUMN IF NOT EXISTS submission_payload jsonb;

ALTER TABLE public.disbursement_confirmations
  ADD COLUMN IF NOT EXISTS amount_mode text,
  ADD COLUMN IF NOT EXISTS client_submission_id uuid,
  ADD COLUMN IF NOT EXISTS request_payload jsonb;

ALTER TABLE public.financial_adjustments
  ADD COLUMN IF NOT EXISTS adjustment_date date,
  ADD COLUMN IF NOT EXISTS exchange_rate_to_ghs numeric(18,8),
  ADD COLUMN IF NOT EXISTS exchange_rate_date date,
  ADD COLUMN IF NOT EXISTS exchange_rate_source text,
  ADD COLUMN IF NOT EXISTS rejected_by uuid,
  ADD COLUMN IF NOT EXISTS rejected_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS client_submission_id uuid,
  ADD COLUMN IF NOT EXISTS submission_payload jsonb;

ALTER TABLE public.disbursements
  DROP CONSTRAINT IF EXISTS disbursements_status_check,
  DROP CONSTRAINT IF EXISTS disbursements_check,
  DROP CONSTRAINT IF EXISTS disbursements_settled_short_check;

ALTER TABLE public.disbursements
  ADD CONSTRAINT disbursements_status_check
    CHECK (status = ANY (ARRAY[
      'awaiting_confirmation'::text,
      'partially_confirmed'::text,
      'confirmed'::text,
      'disputed'::text,
      'settled_short'::text,
      'reconciliation_required'::text,
      'cancelled'::text
    ])),
  ADD CONSTRAINT disbursements_check
    CHECK (
      status NOT IN ('confirmed', 'settled_short')
      OR (amount_received IS NOT NULL AND received_date IS NOT NULL)
    ) NOT VALID,
  ADD CONSTRAINT disbursements_settled_short_check
    CHECK (
      status <> 'settled_short'
      OR (
        effective_amount_received < amount_sent
        AND nullif(btrim(settlement_note), '') IS NOT NULL
        AND settled_short_approved_by IS NOT NULL
        AND settled_short_approved_at IS NOT NULL
        AND settled_short_approved_by <> created_by
      )
    ) NOT VALID,
  ADD CONSTRAINT disbursements_confirmed_amount_check
    CHECK (
      status <> 'confirmed'
      OR effective_amount_received = amount_sent
    ) NOT VALID,
  ADD CONSTRAINT disbursements_partial_amount_check
    CHECK (
      status <> 'partially_confirmed'
      OR (
        effective_amount_received > 0
        AND effective_amount_received < amount_sent
      )
    ) NOT VALID,
  ADD CONSTRAINT disbursements_reconciliation_amount_check
    CHECK (
      status <> 'reconciliation_required'
      OR effective_amount_received > amount_sent
    ) NOT VALID,
  ADD CONSTRAINT disbursements_effective_amount_nonnegative_check
    CHECK (effective_amount_received IS NULL OR effective_amount_received >= 0) NOT VALID,
  ADD CONSTRAINT disbursements_settled_short_approved_by_fkey
    FOREIGN KEY (settled_short_approved_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE public.financial_adjustments
  DROP CONSTRAINT IF EXISTS financial_adjustments_adjustment_type_check,
  ADD CONSTRAINT financial_adjustments_adjustment_type_check
    CHECK (adjustment_type = ANY (ARRAY[
      'correction'::text,
      'reimbursement'::text,
      'reversal'::text,
      'carry_forward'::text,
      'other'::text
    ])),
  ADD CONSTRAINT financial_adjustments_rejection_check
    CHECK (
      status <> 'rejected'
      OR (
        rejected_by IS NOT NULL
        AND rejected_at IS NOT NULL
        AND nullif(btrim(rejection_reason), '') IS NOT NULL
      )
    ) NOT VALID,
  ADD CONSTRAINT financial_adjustments_rejected_by_fkey
    FOREIGN KEY (rejected_by) REFERENCES public.app_users(id) ON DELETE RESTRICT;

ALTER TABLE public.expenses
  ADD CONSTRAINT expenses_over_funds_note_check
    CHECK (NOT over_funds_flag OR nullif(btrim(over_funds_note), '') IS NOT NULL) NOT VALID;

ALTER TABLE public.disbursement_confirmations
  ADD CONSTRAINT disbursement_confirmations_amount_mode_check
    CHECK (amount_mode IS NULL OR amount_mode = ANY (ARRAY['incremental'::text, 'cumulative'::text])) NOT VALID,
  ADD CONSTRAINT disbursement_confirmations_client_submission_id_check
    CHECK (client_submission_id IS NULL OR decision IN ('confirm', 'dispute')) NOT VALID;

CREATE UNIQUE INDEX IF NOT EXISTS disbursement_confirmations_idempotency_idx
  ON public.disbursement_confirmations (confirmed_by, decision, client_submission_id)
  WHERE client_submission_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS disbursements_idempotency_idx
  ON public.disbursements (created_by, client_submission_id)
  WHERE client_submission_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS financial_adjustments_idempotency_idx
  ON public.financial_adjustments (requested_by, client_submission_id)
  WHERE client_submission_id IS NOT NULL;

CREATE TABLE public.expense_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  expense_id uuid NOT NULL,
  expense_category_id uuid NOT NULL,
  line_number integer NOT NULL,
  description text NOT NULL,
  amount numeric(14,2) NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT expense_lines_pkey PRIMARY KEY (id),
  CONSTRAINT expense_lines_expense_id_fkey
    FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE RESTRICT,
  CONSTRAINT expense_lines_expense_category_id_fkey
    FOREIGN KEY (expense_category_id) REFERENCES public.expense_categories(id) ON DELETE RESTRICT,
  CONSTRAINT expense_lines_amount_check CHECK (amount > 0),
  CONSTRAINT expense_lines_line_number_check CHECK (line_number > 0),
  CONSTRAINT expense_lines_description_check CHECK (nullif(btrim(description), '') IS NOT NULL),
  CONSTRAINT expense_lines_expense_line_number_key UNIQUE (expense_id, line_number)
);

CREATE INDEX expense_lines_expense_idx ON public.expense_lines (expense_id, line_number);

CREATE TABLE public.disbursement_resolutions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  disbursement_id uuid NOT NULL,
  resolution_type text NOT NULL,
  resolved_by uuid NOT NULL,
  notes text NOT NULL,
  financial_adjustment_id uuid,
  previous_status text NOT NULL,
  new_status text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT disbursement_resolutions_pkey PRIMARY KEY (id),
  CONSTRAINT disbursement_resolutions_disbursement_id_fkey
    FOREIGN KEY (disbursement_id) REFERENCES public.disbursements(id) ON DELETE RESTRICT,
  CONSTRAINT disbursement_resolutions_resolved_by_fkey
    FOREIGN KEY (resolved_by) REFERENCES public.app_users(id) ON DELETE RESTRICT,
  CONSTRAINT disbursement_resolutions_adjustment_id_fkey
    FOREIGN KEY (financial_adjustment_id) REFERENCES public.financial_adjustments(id) ON DELETE RESTRICT,
  CONSTRAINT disbursement_resolutions_type_check
    CHECK (resolution_type = ANY (ARRAY['resolve_dispute'::text, 'settle_short'::text, 'reconcile_overpayment'::text])),
  CONSTRAINT disbursement_resolutions_notes_check CHECK (nullif(btrim(notes), '') IS NOT NULL)
);

CREATE INDEX disbursement_resolutions_disbursement_created_idx
  ON public.disbursement_resolutions (disbursement_id, created_at DESC);

ALTER TABLE public.expense_receipts
  ADD COLUMN IF NOT EXISTS supersedes_receipt_id uuid;

ALTER TABLE public.file_assets
  ADD COLUMN IF NOT EXISTS content_signature_verified_at timestamp with time zone;

ALTER TABLE public.expense_receipts
  ADD CONSTRAINT expense_receipts_supersedes_receipt_id_fkey
    FOREIGN KEY (supersedes_receipt_id) REFERENCES public.expense_receipts(id) ON DELETE RESTRICT,
  ADD CONSTRAINT expense_receipts_not_self_superseding_check
    CHECK (supersedes_receipt_id IS NULL OR supersedes_receipt_id <> id);

CREATE UNIQUE INDEX expense_receipts_one_replacement_idx
  ON public.expense_receipts (supersedes_receipt_id)
  WHERE supersedes_receipt_id IS NOT NULL;

CREATE UNIQUE INDEX financial_adjustments_one_reversal_idx
  ON public.financial_adjustments (reversal_of_id)
  WHERE reversal_of_id IS NOT NULL AND status IN ('pending', 'approved');

CREATE UNIQUE INDEX financial_adjustments_one_carry_forward_idx
  ON public.financial_adjustments (disbursement_id, reporting_period_id)
  WHERE adjustment_type = 'carry_forward' AND status IN ('pending', 'approved');

DO $seed_categories$
DECLARE
  category_record record;
BEGIN
  FOR category_record IN
    SELECT *
    FROM (VALUES
      ('fuel', 'Fuel'),
      ('vehicle_servicing_maintenance', 'Vehicle Servicing & Maintenance'),
      ('vehicle_parts_repairs', 'Vehicle Parts & Repairs'),
      ('engine_oil_lubricants', 'Engine Oil & Lubricants'),
      ('travel_transport_general', 'Travel & Transport (General)'),
      ('field_outreach_ministry', 'Field Outreach & Ministry'),
      ('supplies_materials', 'Supplies & Materials'),
      ('communication_data', 'Communication & Data'),
      ('accommodation_meals', 'Accommodation & Meals'),
      ('admin_banking_fees', 'Admin & Banking Fees'),
      ('miscellaneous_other', 'Miscellaneous / Other')
    ) AS approved(code, name)
  LOOP
    IF EXISTS (
      SELECT 1
      FROM public.expense_categories
      WHERE (code = category_record.code AND name <> category_record.name)
         OR (name = category_record.name AND code <> category_record.code)
    ) THEN
      RAISE EXCEPTION 'Expense category code/name conflict for %', category_record.code;
    END IF;

    INSERT INTO public.expense_categories (code, name, is_active, receipt_required)
    VALUES (category_record.code, category_record.name, true, true)
    ON CONFLICT (code) DO UPDATE
      SET is_active = true,
          receipt_required = true,
          updated_at = now();
  END LOOP;
END;
$seed_categories$;

INSERT INTO public.permissions (code, module, description, is_sensitive)
VALUES
  ('financial.expenses.own_manage', 'finance', 'Manage own draft and queried expenses only.', true),
  ('financial.disbursements.own_confirm', 'finance', 'Confirm or dispute disbursements assigned to own missionary record.', true),
  ('financial.disbursements.create', 'finance', 'Create disbursements as Office Staff.', true),
  ('financial.disbursements.evidence', 'finance', 'Attach payment evidence to disbursements created by Office Staff.', true)
ON CONFLICT (code) DO UPDATE
  SET module = EXCLUDED.module,
      description = EXCLUDED.description,
      is_sensitive = true;

DO $required_finance_roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.roles WHERE code = 'missionary')
     OR NOT EXISTS (SELECT 1 FROM public.roles WHERE code = 'office_staff') THEN
    RAISE EXCEPTION 'Stage 3 requires the existing missionary and office_staff roles.';
  END IF;
END;
$required_finance_roles$;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT role_row.id, permission_row.id
FROM (
  VALUES
    ('missionary', 'financial.expenses.own_manage'),
    ('missionary', 'financial.disbursements.own_confirm'),
    ('office_staff', 'financial.disbursements.create'),
    ('office_staff', 'financial.disbursements.evidence')
) AS assignment(role_code, permission_code)
JOIN public.roles AS role_row ON role_row.code = assignment.role_code
JOIN public.permissions AS permission_row ON permission_row.code = assignment.permission_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

CREATE OR REPLACE FUNCTION private.finance_validate_period_date(
  p_reporting_period_id uuid,
  p_transaction_date date
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  period_row public.reporting_periods%ROWTYPE;
BEGIN
  SELECT *
  INTO period_row
  FROM public.reporting_periods
  WHERE id = p_reporting_period_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reporting period not found.' USING ERRCODE = '23503';
  END IF;

  IF period_row.year < 2027
     OR p_transaction_date IS NULL
     OR p_transaction_date < period_row.start_date
     OR p_transaction_date > period_row.end_date THEN
    RAISE EXCEPTION 'Financial transaction date must be within its 2027+ reporting period.'
      USING ERRCODE = '23514';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_validate_fx(
  p_currency character(3),
  p_rate numeric,
  p_rate_date date,
  p_rate_source text
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $function$
BEGIN
  IF p_currency = 'GHS' THEN
    IF p_rate IS DISTINCT FROM 1.0::numeric THEN
      RAISE EXCEPTION 'GHS transactions must use an exchange rate of 1.0.'
        USING ERRCODE = '23514';
    END IF;
  ELSIF p_rate IS NULL
     OR p_rate <= 0
     OR p_rate_date IS NULL
     OR nullif(btrim(p_rate_source), '') IS NULL THEN
    RAISE EXCEPTION 'Non-GHS transactions require a positive rate, rate date, and source.'
      USING ERRCODE = '23514';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_transaction_period_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  period_id uuid;
  transaction_date date;
BEGIN
  IF TG_TABLE_NAME = 'expenses' THEN
    period_id := NEW.reporting_period_id;
    transaction_date := NEW.expense_date;
  ELSIF TG_TABLE_NAME = 'disbursements' THEN
    period_id := NEW.reporting_period_id;
    transaction_date := NEW.sent_date;
  ELSIF TG_TABLE_NAME = 'financial_adjustments' THEN
    period_id := NEW.reporting_period_id;
    transaction_date := NEW.adjustment_date;
  ELSIF TG_TABLE_NAME = 'disbursement_confirmations' THEN
    IF NEW.decision <> 'confirm' THEN
      RETURN NEW;
    END IF;
    SELECT reporting_period_id INTO period_id
    FROM public.disbursements
    WHERE id = NEW.disbursement_id;
    transaction_date := NEW.received_date;
  ELSE
    RETURN NEW;
  END IF;

  PERFORM private.finance_validate_period_date(period_id, transaction_date);
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_reporting_period_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF NEW.year < 2027
     OR NEW.year > 2100
     OR NEW.start_date < DATE '2027-01-01'
     OR NEW.end_date < NEW.start_date
     OR NEW.end_date > DATE '2100-12-31'
     OR extract(year FROM NEW.start_date)::integer <> NEW.year
     OR extract(year FROM NEW.end_date)::integer <> NEW.year THEN
    RAISE EXCEPTION 'Stage 3 reporting periods must be valid 2027–2100 periods.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_reporting_period_scope
  BEFORE INSERT OR UPDATE OF year, start_date, end_date ON public.reporting_periods
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_reporting_period_guard();

CREATE TRIGGER stage3_expense_period_scope
  BEFORE INSERT OR UPDATE OF reporting_period_id, expense_date ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_transaction_period_guard();

CREATE TRIGGER stage3_disbursement_period_scope
  BEFORE INSERT OR UPDATE OF reporting_period_id, sent_date ON public.disbursements
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_transaction_period_guard();

CREATE TRIGGER stage3_adjustment_period_scope
  BEFORE INSERT OR UPDATE OF reporting_period_id, adjustment_date ON public.financial_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_transaction_period_guard();

CREATE TRIGGER stage3_confirmation_period_scope
  BEFORE INSERT OR UPDATE OF disbursement_id, decision, received_date ON public.disbursement_confirmations
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_transaction_period_guard();

CREATE OR REPLACE FUNCTION private.finance_fx_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  PERFORM private.finance_validate_fx(
    NEW.currency,
    NEW.exchange_rate_to_ghs,
    NEW.exchange_rate_date,
    NEW.exchange_rate_source
  );
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_expense_fx_guard
  BEFORE INSERT OR UPDATE OF currency, exchange_rate_to_ghs, exchange_rate_date, exchange_rate_source
  ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_fx_guard();

CREATE TRIGGER stage3_disbursement_fx_guard
  BEFORE INSERT OR UPDATE OF currency, exchange_rate_to_ghs, exchange_rate_date, exchange_rate_source
  ON public.disbursements
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_fx_guard();

CREATE TRIGGER stage3_adjustment_fx_guard
  BEFORE INSERT OR UPDATE OF currency, exchange_rate_to_ghs, exchange_rate_date, exchange_rate_source
  ON public.financial_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_fx_guard();

CREATE OR REPLACE FUNCTION private.finance_owns_missionary(p_missionary_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.missionaries AS missionary
    WHERE missionary.id = p_missionary_id
      AND missionary.app_user_id = (SELECT auth.uid())
      AND missionary.status = 'active'
  );
$function$;

CREATE OR REPLACE FUNCTION private.finance_period_lock(p_reporting_period_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM 1
  FROM public.reporting_periods
  WHERE id = p_reporting_period_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reporting period not found.' USING ERRCODE = '23503';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_audit_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  before_row jsonb;
  after_row jsonb;
  record_id uuid;
BEGIN
  IF TG_TABLE_NAME = 'expenses'
     AND TG_OP = 'UPDATE'
     AND pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  IF TG_OP <> 'INSERT' THEN
    before_row := to_jsonb(OLD);
    record_id := OLD.id;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    after_row := to_jsonb(NEW);
    record_id := NEW.id;
  END IF;

  INSERT INTO public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    before_values,
    after_values
  )
  VALUES (
    (SELECT auth.uid()),
    'finance_' || lower(TG_OP),
    'finance.' || TG_TABLE_NAME,
    record_id,
    before_row,
    after_row
  );

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_guard_expense_line()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  expense_row public.expenses%ROWTYPE;
  category_allowed boolean;
BEGIN
  SELECT *
  INTO expense_row
  FROM public.expenses
  WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.expense_id ELSE NEW.expense_id END
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Expense not found.' USING ERRCODE = '23503';
  END IF;

  IF NOT private.is_active_user()
     OR NOT private.has_permission('financial.expenses.own_manage')
     OR NOT private.finance_owns_missionary(expense_row.missionary_id) THEN
    RAISE EXCEPTION 'Not authorized to edit this expense.'
      USING ERRCODE = '42501';
  END IF;

  IF expense_row.status NOT IN ('draft', 'queried') THEN
    RAISE EXCEPTION 'Expense lines can only change while an expense is draft or queried.'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.expense_id <> OLD.expense_id THEN
    RAISE EXCEPTION 'An expense line cannot be moved to another expense.'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP <> 'DELETE' THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.expense_categories AS category
      WHERE category.id = NEW.expense_category_id
        AND category.is_active
        AND category.code = ANY (ARRAY[
          'fuel',
          'vehicle_servicing_maintenance',
          'vehicle_parts_repairs',
          'engine_oil_lubricants',
          'travel_transport_general',
          'field_outreach_ministry',
          'supplies_materials',
          'communication_data',
          'accommodation_meals',
          'admin_banking_fees',
          'miscellaneous_other'
        ])
    )
    INTO category_allowed;

    IF NOT category_allowed THEN
      RAISE EXCEPTION 'Expense line category is not one of the approved active categories.'
        USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := now();
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_sync_expense_header()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  target_expense_id uuid;
  line_count bigint;
  category_count bigint;
  header_amount numeric(14,2);
  summary_category_id uuid;
BEGIN
  target_expense_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.expense_id ELSE NEW.expense_id END;

  SELECT count(*), coalesce(sum(line.amount), 0)::numeric(14,2), count(DISTINCT line.expense_category_id)
  INTO line_count, header_amount, category_count
  FROM public.expense_lines AS line
  WHERE line.expense_id = target_expense_id;

  IF line_count = 0 THEN
    RAISE EXCEPTION 'An itemised expense must retain at least one line.'
      USING ERRCODE = '23514';
  END IF;

  IF category_count = 1 THEN
    SELECT line.expense_category_id
    INTO summary_category_id
    FROM public.expense_lines AS line
    WHERE line.expense_id = target_expense_id
    ORDER BY line.line_number
    LIMIT 1;
  ELSE
    summary_category_id := NULL;
  END IF;

  UPDATE public.expenses
  SET amount = header_amount,
      expense_category_id = summary_category_id,
      updated_at = now()
  WHERE id = target_expense_id;

  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_prevent_expense_header_override()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF pg_trigger_depth() = 1
     AND (
       NEW.amount IS DISTINCT FROM OLD.amount
       OR NEW.expense_category_id IS DISTINCT FROM OLD.expense_category_id
     ) THEN
    RAISE EXCEPTION 'Expense header amount and summary category are derived from item lines.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_expense_line_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.expense_lines
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_expense_line();

CREATE TRIGGER stage3_expense_line_sync_header
  AFTER INSERT OR UPDATE OR DELETE ON public.expense_lines
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_sync_expense_header();

CREATE TRIGGER stage3_expense_header_derived_fields
  BEFORE UPDATE OF amount, expense_category_id ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_prevent_expense_header_override();

CREATE OR REPLACE FUNCTION private.finance_validate_receipt_file(p_file_asset_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  asset public.file_assets%ROWTYPE;
  file_extension text;
  valid_pair boolean;
BEGIN
  SELECT *
  INTO asset
  FROM public.file_assets
  WHERE id = p_file_asset_id;

  IF NOT FOUND
     OR asset.upload_status <> 'uploaded'
     OR asset.deleted_at IS NOT NULL
     OR asset.content_signature_verified_at IS NULL THEN
    RAISE EXCEPTION 'Receipt file must be fully uploaded, available, and signature-verified by the trusted upload path.'
      USING ERRCODE = '23514';
  END IF;

  IF asset.size_bytes > 5000000 THEN
    RAISE EXCEPTION 'Financial receipt files may not exceed 5 MB.'
      USING ERRCODE = '23514';
  END IF;

  file_extension := lower(substring(asset.original_filename from '\.([^.]+)$'));
  valid_pair := CASE asset.content_type
    WHEN 'image/jpeg' THEN file_extension = ANY (ARRAY['jpg', 'jpeg'])
    WHEN 'image/png' THEN file_extension = 'png'
    WHEN 'image/webp' THEN file_extension = 'webp'
    WHEN 'application/pdf' THEN file_extension = 'pdf'
    ELSE false
  END;

  IF NOT valid_pair THEN
    RAISE EXCEPTION 'Financial receipts must be matching JPEG, PNG, WebP, or PDF files.'
      USING ERRCODE = '23514';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_guard_expense_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  expense_row public.expenses%ROWTYPE;
  active_count bigint;
  replacement_count bigint := 0;
  prior_receipt public.expense_receipts%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Expense receipt links are append-only; create a replacement link instead.'
      USING ERRCODE = '23514';
  END IF;

  SELECT *
  INTO expense_row
  FROM public.expenses
  WHERE id = NEW.expense_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Expense not found.' USING ERRCODE = '23503';
  END IF;

  IF expense_row.status NOT IN ('draft', 'queried')
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.expenses.own_manage')
     OR NOT private.finance_owns_missionary(expense_row.missionary_id) THEN
    RAISE EXCEPTION 'Receipts can only be added to an authorized draft or queried expense.'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.uploaded_by <> (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Receipt uploader must be the authenticated actor.'
      USING ERRCODE = '42501';
  END IF;

  PERFORM private.finance_validate_receipt_file(NEW.file_asset_id);
  IF NOT EXISTS (
    SELECT 1
    FROM public.file_assets
    WHERE id = NEW.file_asset_id
      AND uploaded_by = (SELECT auth.uid())
  ) THEN
    RAISE EXCEPTION 'A receipt may only link a file uploaded by the authenticated actor.'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.supersedes_receipt_id IS NOT NULL THEN
    SELECT *
    INTO prior_receipt
    FROM public.expense_receipts
    WHERE id = NEW.supersedes_receipt_id
      AND expense_id = NEW.expense_id
    FOR UPDATE;

    IF NOT FOUND OR EXISTS (
      SELECT 1
      FROM public.expense_receipts AS child
      WHERE child.supersedes_receipt_id = prior_receipt.id
    ) THEN
      RAISE EXCEPTION 'Only an active receipt for this expense can be replaced.'
        USING ERRCODE = '23514';
    END IF;
    replacement_count := 1;
  END IF;

  SELECT count(*)
  INTO active_count
  FROM public.expense_receipts AS receipt
  WHERE receipt.expense_id = NEW.expense_id
    AND NOT EXISTS (
      SELECT 1
      FROM public.expense_receipts AS replacement
      WHERE replacement.supersedes_receipt_id = receipt.id
    );

  IF active_count + 1 - replacement_count > 5 THEN
    RAISE EXCEPTION 'An expense may have no more than five active receipts.'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_expense_receipt_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.expense_receipts
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_expense_receipt();

CREATE OR REPLACE FUNCTION private.finance_guard_disbursement_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  disbursement_row public.disbursements%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Payment evidence links are append-only.'
      USING ERRCODE = '23514';
  END IF;

  SELECT *
  INTO disbursement_row
  FROM public.disbursements
  WHERE id = NEW.disbursement_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Disbursement not found.' USING ERRCODE = '23503';
  END IF;

  IF NEW.uploaded_by <> (SELECT auth.uid())
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.disbursements.evidence')
     OR disbursement_row.created_by <> (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized to attach evidence to this disbursement.'
      USING ERRCODE = '42501';
  END IF;

  PERFORM private.finance_validate_receipt_file(NEW.file_asset_id);
  IF NOT EXISTS (
    SELECT 1
    FROM public.file_assets
    WHERE id = NEW.file_asset_id
      AND uploaded_by = (SELECT auth.uid())
  ) THEN
    RAISE EXCEPTION 'Payment evidence may only link a file uploaded by the authenticated actor.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_disbursement_receipt_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.disbursement_receipts
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_disbursement_receipt();

CREATE TRIGGER stage3_finance_audit_expenses
  AFTER INSERT OR UPDATE OR DELETE ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();
CREATE TRIGGER stage3_finance_audit_expense_lines
  AFTER INSERT OR UPDATE OR DELETE ON public.expense_lines
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();
CREATE TRIGGER stage3_finance_audit_expense_receipts
  AFTER INSERT OR UPDATE OR DELETE ON public.expense_receipts
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();
CREATE TRIGGER stage3_finance_audit_expense_reviews
  AFTER INSERT OR UPDATE OR DELETE ON public.expense_reviews
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();
CREATE TRIGGER stage3_finance_audit_disbursements
  AFTER INSERT OR UPDATE OR DELETE ON public.disbursements
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();
CREATE TRIGGER stage3_finance_audit_disbursement_confirmations
  AFTER INSERT OR UPDATE OR DELETE ON public.disbursement_confirmations
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();
CREATE TRIGGER stage3_finance_audit_disbursement_receipts
  AFTER INSERT OR UPDATE OR DELETE ON public.disbursement_receipts
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();
CREATE TRIGGER stage3_finance_audit_adjustments
  AFTER INSERT OR UPDATE OR DELETE ON public.financial_adjustments
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();
CREATE TRIGGER stage3_finance_audit_resolutions
  AFTER INSERT OR UPDATE OR DELETE ON public.disbursement_resolutions
  FOR EACH ROW EXECUTE FUNCTION private.finance_audit_row();

CREATE OR REPLACE FUNCTION private.finance_guard_confirmation_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  parent_disbursement public.disbursements%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Disbursement confirmation events are append-only.'
      USING ERRCODE = '23514';
  END IF;

  IF NOT private.is_active_user()
     OR NOT private.has_permission('financial.disbursements.own_confirm')
     OR NEW.confirmed_by <> (SELECT auth.uid())
     OR NEW.client_submission_id IS NULL
     OR NEW.request_payload IS NULL THEN
    RAISE EXCEPTION 'Confirmation event requires an active authorized actor and idempotency payload.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO parent_disbursement
  FROM public.disbursements
  WHERE id = NEW.disbursement_id;
  IF NOT FOUND
     OR NOT private.finance_owns_missionary(parent_disbursement.missionary_id) THEN
    RAISE EXCEPTION 'Confirmation event must belong to the actor''s active missionary record.'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.decision = 'confirm' THEN
    IF NEW.amount_received IS NULL
       OR NEW.amount_received <= 0
       OR NEW.amount_mode IS NULL
       OR NEW.amount_mode NOT IN ('incremental', 'cumulative')
       OR NEW.received_date IS NULL THEN
      RAISE EXCEPTION 'Confirmation events require a positive amount, mode, and date.'
        USING ERRCODE = '23514';
    END IF;
  ELSIF NEW.decision = 'dispute' THEN
    IF NEW.amount_received IS NOT NULL
       OR NEW.amount_mode IS NOT NULL
       OR NEW.received_date IS NOT NULL
       OR nullif(btrim(NEW.notes), '') IS NULL THEN
      RAISE EXCEPTION 'Dispute events require notes and cannot include a receipt amount.'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_confirmation_event_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.disbursement_confirmations
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_confirmation_event();

CREATE OR REPLACE FUNCTION private.finance_guard_expense_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  expense_row public.expenses%ROWTYPE;
  expected_status text;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Expense review decisions are append-only.'
      USING ERRCODE = '23514';
  END IF;

  IF NOT private.is_active_user()
     OR NOT private.has_permission('financial.manage')
     OR NEW.reviewer_id <> (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Expense reviews require an active Financial Director actor.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO expense_row
  FROM public.expenses
  WHERE id = NEW.expense_id;
  IF NOT FOUND
     OR expense_row.created_by = NEW.reviewer_id
     OR EXISTS (
       SELECT 1 FROM public.missionaries AS missionary
       WHERE missionary.id = expense_row.missionary_id
         AND missionary.app_user_id = NEW.reviewer_id
     ) THEN
    RAISE EXCEPTION 'A reviewer cannot review their own expense.'
      USING ERRCODE = '42501';
  END IF;

  expected_status := CASE NEW.decision
    WHEN 'approve' THEN 'approved'
    WHEN 'request_clarification' THEN 'queried'
    WHEN 'reject' THEN 'rejected'
    ELSE NULL
  END;
  IF NEW.previous_status <> 'submitted'
     OR NEW.new_status IS DISTINCT FROM expected_status
     OR expense_row.status IS DISTINCT FROM expected_status
     OR (NEW.decision <> 'approve' AND nullif(btrim(NEW.comments), '') IS NULL) THEN
    RAISE EXCEPTION 'Review decision does not match the recorded expense transition.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_expense_review_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.expense_reviews
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_expense_review();

CREATE OR REPLACE FUNCTION private.finance_guard_resolution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  parent_disbursement public.disbursements%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Disbursement resolution records are append-only.'
      USING ERRCODE = '23514';
  END IF;
  IF NOT private.is_active_user()
     OR NOT private.has_permission('financial.manage')
     OR NEW.resolved_by <> (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Disbursement resolution requires an active Financial Director actor.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO parent_disbursement
  FROM public.disbursements
  WHERE id = NEW.disbursement_id;
  IF NOT FOUND
     OR parent_disbursement.created_by = NEW.resolved_by
     OR parent_disbursement.status IS DISTINCT FROM NEW.new_status
     OR NEW.previous_status = NEW.new_status THEN
    RAISE EXCEPTION 'Resolution actor or before/after state is invalid.'
      USING ERRCODE = '23514';
  END IF;
  IF NEW.resolution_type = 'settle_short'
     AND (
       NEW.new_status <> 'settled_short'
       OR NEW.previous_status NOT IN ('partially_confirmed', 'disputed')
     ) THEN
    RAISE EXCEPTION 'Settled-short resolution must produce settled_short.'
      USING ERRCODE = '23514';
  END IF;
  IF NEW.resolution_type = 'resolve_dispute'
     AND NEW.previous_status <> 'disputed' THEN
    RAISE EXCEPTION 'Only a disputed disbursement may be cleared.'
      USING ERRCODE = '23514';
  END IF;
  IF NEW.resolution_type = 'reconcile_overpayment'
     AND (
       NEW.new_status <> 'confirmed'
       OR NEW.financial_adjustment_id IS NULL
       OR NEW.previous_status <> 'reconciliation_required'
       OR NOT EXISTS (
         SELECT 1
         FROM public.financial_adjustments AS adjustment
         WHERE adjustment.id = NEW.financial_adjustment_id
           AND adjustment.disbursement_id = NEW.disbursement_id
           AND adjustment.status = 'approved'
           AND adjustment.adjustment_type NOT IN ('carry_forward', 'reimbursement')
       )
     ) THEN
    RAISE EXCEPTION 'Overpayment resolution requires an approved linked adjustment and exact confirmation.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_disbursement_resolution_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.disbursement_resolutions
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_resolution();

CREATE OR REPLACE FUNCTION private.finance_guard_adjustment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  source_missionary_id uuid;
  source_period_id uuid;
  source_currency character(3);
  original_adjustment public.financial_adjustments%ROWTYPE;
  source_period public.reporting_periods%ROWTYPE;
  target_period public.reporting_periods%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Financial adjustments are append-only.'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NOT private.is_active_user()
       OR NOT private.has_permission('financial.manage')
       OR NEW.requested_by <> (SELECT auth.uid())
       OR NEW.status <> 'pending'
       OR NEW.approved_by IS NOT NULL
       OR NEW.approved_at IS NOT NULL
       OR NEW.client_submission_id IS NULL
       OR NEW.submission_payload IS NULL THEN
      RAISE EXCEPTION 'A pending adjustment must be requested by an active Financial Director.'
        USING ERRCODE = '42501';
    END IF;

    IF NEW.disbursement_id IS NOT NULL THEN
      SELECT missionary_id, reporting_period_id, currency
      INTO source_missionary_id, source_period_id, source_currency
      FROM public.disbursements
      WHERE id = NEW.disbursement_id;
    ELSE
      SELECT missionary_id, reporting_period_id, currency
      INTO source_missionary_id, source_period_id, source_currency
      FROM public.expenses
      WHERE id = NEW.expense_id;
    END IF;
    IF NOT FOUND OR source_missionary_id <> NEW.missionary_id THEN
      RAISE EXCEPTION 'Adjustment target and missionary must match.'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.adjustment_type = 'carry_forward' THEN
      IF NEW.disbursement_id IS NULL
         OR NEW.expense_id IS NOT NULL
         OR NEW.currency <> source_currency
         OR NEW.amount <= 0 THEN
        RAISE EXCEPTION 'Carry-forward must be positive and linked to its source disbursement currency.'
          USING ERRCODE = '23514';
      END IF;
      SELECT * INTO source_period
      FROM public.reporting_periods
      WHERE id = source_period_id;
      SELECT * INTO target_period
      FROM public.reporting_periods
      WHERE id = NEW.reporting_period_id;
      IF source_period.year < 2027
         OR target_period.year < 2027
         OR source_period.period_type <> target_period.period_type
         OR target_period.start_date <> source_period.end_date + 1 THEN
        RAISE EXCEPTION 'Carry-forward must target the immediately following 2027+ reporting period.'
          USING ERRCODE = '23514';
      END IF;
    ELSIF NEW.adjustment_type <> 'reversal'
       AND (
         NEW.reporting_period_id <> source_period_id
         OR NEW.currency <> source_currency
       ) THEN
      RAISE EXCEPTION 'Linked adjustments must match the target period and native currency.'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.adjustment_type = 'reversal' THEN
      SELECT * INTO original_adjustment
      FROM public.financial_adjustments
      WHERE id = NEW.reversal_of_id;
      IF NOT FOUND
         OR original_adjustment.status <> 'approved'
         OR original_adjustment.reversal_of_id IS NOT NULL
         OR NEW.amount <> -original_adjustment.amount
         OR NEW.currency <> original_adjustment.currency
         OR NEW.exchange_rate_to_ghs IS DISTINCT FROM original_adjustment.exchange_rate_to_ghs
         OR NEW.exchange_rate_date IS DISTINCT FROM original_adjustment.exchange_rate_date
         OR NEW.exchange_rate_source IS DISTINCT FROM original_adjustment.exchange_rate_source
         OR NEW.disbursement_id IS DISTINCT FROM original_adjustment.disbursement_id
         OR NEW.expense_id IS DISTINCT FROM original_adjustment.expense_id
         OR NEW.reporting_period_id <> original_adjustment.reporting_period_id THEN
        RAISE EXCEPTION 'Reversal must exactly negate one approved original and cannot chain.'
          USING ERRCODE = '23514';
      END IF;
    ELSIF NEW.reversal_of_id IS NOT NULL THEN
      RAISE EXCEPTION 'Only reversal adjustments may set reversal_of_id.'
        USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
  END IF;

  IF OLD.status <> 'pending'
     OR NEW.status NOT IN ('approved', 'rejected')
     OR NEW.id IS DISTINCT FROM OLD.id
     OR NEW.missionary_id IS DISTINCT FROM OLD.missionary_id
     OR NEW.reporting_period_id IS DISTINCT FROM OLD.reporting_period_id
     OR NEW.disbursement_id IS DISTINCT FROM OLD.disbursement_id
     OR NEW.expense_id IS DISTINCT FROM OLD.expense_id
     OR NEW.adjustment_type IS DISTINCT FROM OLD.adjustment_type
     OR NEW.amount IS DISTINCT FROM OLD.amount
     OR NEW.currency IS DISTINCT FROM OLD.currency
     OR NEW.reason IS DISTINCT FROM OLD.reason
     OR NEW.requested_by IS DISTINCT FROM OLD.requested_by
     OR NEW.reversal_of_id IS DISTINCT FROM OLD.reversal_of_id
     OR NEW.adjustment_date IS DISTINCT FROM OLD.adjustment_date
     OR NEW.exchange_rate_to_ghs IS DISTINCT FROM OLD.exchange_rate_to_ghs
     OR NEW.exchange_rate_date IS DISTINCT FROM OLD.exchange_rate_date
     OR NEW.exchange_rate_source IS DISTINCT FROM OLD.exchange_rate_source
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.manage')
     OR OLD.requested_by = (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Only a different active Financial Director may approve or reject a pending adjustment.'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.status = 'approved'
     AND (
       NEW.approved_by IS DISTINCT FROM (SELECT auth.uid())
       OR NEW.approved_at IS NULL
       OR NEW.rejected_by IS NOT NULL
       OR NEW.rejected_at IS NOT NULL
       OR NEW.rejection_reason IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Approval actor and timestamp are required.'
      USING ERRCODE = '23514';
  END IF;
  IF NEW.status = 'rejected'
     AND (
       NEW.rejected_by IS DISTINCT FROM (SELECT auth.uid())
       OR NEW.rejected_at IS NULL
       OR nullif(btrim(NEW.rejection_reason), '') IS NULL
       OR NEW.approved_by IS NOT NULL
       OR NEW.approved_at IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Rejection actor, timestamp, and reason are required.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_financial_adjustment_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.financial_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_adjustment();

CREATE OR REPLACE FUNCTION private.finance_guard_expense_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  owns_expense boolean;
  is_financial_director boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Expenses are retained; cancel unapproved expenses or use adjustments.'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF actor_id IS NULL
       OR NOT private.is_active_user()
       OR NOT private.has_permission('financial.expenses.own_manage')
       OR NEW.created_by <> actor_id
       OR NEW.status <> 'draft'
       OR NEW.client_submission_id IS NULL
       OR NEW.submission_payload IS NULL
       OR NOT private.finance_owns_missionary(NEW.missionary_id) THEN
      RAISE EXCEPTION 'New expenses must be the actor''s own idempotent draft.'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;
  IF actor_id IS NULL OR NOT private.is_active_user() THEN
    RAISE EXCEPTION 'An active user is required to update an expense.'
      USING ERRCODE = '42501';
  END IF;

  owns_expense := private.finance_owns_missionary(OLD.missionary_id);
  is_financial_director := private.has_permission('financial.manage');

  IF owns_expense AND private.has_permission('financial.expenses.own_manage') THEN
    IF NEW.missionary_id IS DISTINCT FROM OLD.missionary_id
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.client_submission_id IS DISTINCT FROM OLD.client_submission_id
       OR NEW.submission_payload IS DISTINCT FROM OLD.submission_payload
       OR (
         NEW.status IS DISTINCT FROM OLD.status
         AND NOT (
           (OLD.status = 'draft' AND NEW.status IN ('submitted', 'cancelled'))
           OR (OLD.status = 'queried' AND NEW.status IN ('submitted', 'cancelled'))
           OR (OLD.status = 'submitted' AND NEW.status = 'cancelled')
         )
       ) THEN
      RAISE EXCEPTION 'Invalid own-expense edit or status transition.'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.status IS NOT DISTINCT FROM OLD.status
       AND OLD.status NOT IN ('draft', 'queried') THEN
      RAISE EXCEPTION 'Only draft or queried expense facts may be edited.'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.status IS NOT DISTINCT FROM OLD.status
       AND (
         NEW.submitted_at IS DISTINCT FROM OLD.submitted_at
         OR NEW.over_funds_flag IS DISTINCT FROM OLD.over_funds_flag
         OR NEW.over_funds_note IS DISTINCT FROM OLD.over_funds_note
       ) THEN
      RAISE EXCEPTION 'Submission metadata can only change through the submit operation.'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status
       AND (
         NEW.reporting_period_id IS DISTINCT FROM OLD.reporting_period_id
         OR NEW.expense_date IS DISTINCT FROM OLD.expense_date
         OR NEW.amount IS DISTINCT FROM OLD.amount
         OR NEW.expense_category_id IS DISTINCT FROM OLD.expense_category_id
         OR NEW.currency IS DISTINCT FROM OLD.currency
         OR NEW.exchange_rate_to_ghs IS DISTINCT FROM OLD.exchange_rate_to_ghs
         OR NEW.exchange_rate_date IS DISTINCT FROM OLD.exchange_rate_date
         OR NEW.exchange_rate_source IS DISTINCT FROM OLD.exchange_rate_source
         OR NEW.description IS DISTINCT FROM OLD.description
       ) THEN
      RAISE EXCEPTION 'A status transition cannot modify expense facts.'
        USING ERRCODE = '23514';
    END IF;
    IF NEW.status = 'submitted' THEN
      IF NEW.submitted_at IS NULL THEN
        RAISE EXCEPTION 'Submitted expenses require a server-assigned submission time.'
          USING ERRCODE = '23514';
      END IF;
    ELSIF NEW.submitted_at IS DISTINCT FROM OLD.submitted_at
       OR NEW.over_funds_flag IS DISTINCT FROM OLD.over_funds_flag
       OR NEW.over_funds_note IS DISTINCT FROM OLD.over_funds_note THEN
      RAISE EXCEPTION 'Cancellation cannot rewrite submission metadata.'
        USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF is_financial_director
     AND OLD.status = 'submitted'
     AND NEW.status IN ('approved', 'queried', 'rejected')
     AND NEW.missionary_id IS NOT DISTINCT FROM OLD.missionary_id
     AND NEW.reporting_period_id IS NOT DISTINCT FROM OLD.reporting_period_id
     AND NEW.expense_category_id IS NOT DISTINCT FROM OLD.expense_category_id
     AND NEW.expense_date IS NOT DISTINCT FROM OLD.expense_date
     AND NEW.amount IS NOT DISTINCT FROM OLD.amount
     AND NEW.currency IS NOT DISTINCT FROM OLD.currency
     AND NEW.exchange_rate_to_ghs IS NOT DISTINCT FROM OLD.exchange_rate_to_ghs
     AND NEW.exchange_rate_date IS NOT DISTINCT FROM OLD.exchange_rate_date
     AND NEW.exchange_rate_source IS NOT DISTINCT FROM OLD.exchange_rate_source
     AND NEW.description IS NOT DISTINCT FROM OLD.description
     AND NEW.created_by IS NOT DISTINCT FROM OLD.created_by
     AND NEW.client_submission_id IS NOT DISTINCT FROM OLD.client_submission_id
     AND NEW.submission_payload IS NOT DISTINCT FROM OLD.submission_payload
     AND NEW.submitted_at IS NOT DISTINCT FROM OLD.submitted_at
     AND NEW.over_funds_flag IS NOT DISTINCT FROM OLD.over_funds_flag
     AND NEW.over_funds_note IS NOT DISTINCT FROM OLD.over_funds_note
     AND OLD.created_by <> actor_id
     AND NOT owns_expense THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Expense update is outside the authorized workflow.'
    USING ERRCODE = '42501';
END;
$function$;

CREATE TRIGGER stage3_expense_write_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_expense_write();

CREATE OR REPLACE FUNCTION private.finance_guard_disbursement_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  owns_disbursement boolean;
  is_financial_director boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Disbursements are retained and cannot be deleted.'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF actor_id IS NULL
       OR NOT private.is_active_user()
       OR NOT private.has_permission('financial.disbursements.create')
       OR NEW.created_by <> actor_id
       OR NEW.status <> 'awaiting_confirmation'
       OR NEW.amount_received IS NOT NULL
       OR NEW.effective_amount_received IS DISTINCT FROM 0::numeric
       OR NEW.client_submission_id IS NULL
       OR NEW.submission_payload IS NULL
       OR NOT EXISTS (
         SELECT 1
         FROM public.missionaries AS missionary
         WHERE missionary.id = NEW.missionary_id
           AND missionary.status = 'active'
       ) THEN
      RAISE EXCEPTION 'New disbursements must be authorized, idempotent, and awaiting confirmation.'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF actor_id IS NULL OR NOT private.is_active_user() THEN
    RAISE EXCEPTION 'An active user is required to update a disbursement.'
      USING ERRCODE = '42501';
  END IF;
  owns_disbursement := private.finance_owns_missionary(OLD.missionary_id);
  is_financial_director := private.has_permission('financial.manage');

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.reference IS DISTINCT FROM OLD.reference
     OR NEW.missionary_id IS DISTINCT FROM OLD.missionary_id
     OR NEW.reporting_period_id IS DISTINCT FROM OLD.reporting_period_id
     OR NEW.amount_sent IS DISTINCT FROM OLD.amount_sent
     OR NEW.currency IS DISTINCT FROM OLD.currency
     OR NEW.sent_date IS DISTINCT FROM OLD.sent_date
     OR NEW.payment_method IS DISTINCT FROM OLD.payment_method
     OR NEW.transaction_reference IS DISTINCT FROM OLD.transaction_reference
     OR NEW.exchange_rate_to_ghs IS DISTINCT FROM OLD.exchange_rate_to_ghs
     OR NEW.exchange_rate_date IS DISTINCT FROM OLD.exchange_rate_date
     OR NEW.exchange_rate_source IS DISTINCT FROM OLD.exchange_rate_source
     OR NEW.notes IS DISTINCT FROM OLD.notes
     OR NEW.created_by IS DISTINCT FROM OLD.created_by
     OR NEW.client_submission_id IS DISTINCT FROM OLD.client_submission_id
     OR NEW.submission_payload IS DISTINCT FROM OLD.submission_payload THEN
    RAISE EXCEPTION 'Disbursement payment facts are immutable.'
      USING ERRCODE = '23514';
  END IF;

  IF owns_disbursement
     AND private.has_permission('financial.disbursements.own_confirm')
     AND (
       NEW.settlement_note IS DISTINCT FROM OLD.settlement_note
       OR NEW.settled_short_approved_by IS DISTINCT FROM OLD.settled_short_approved_by
       OR NEW.settled_short_approved_at IS DISTINCT FROM OLD.settled_short_approved_at
     ) THEN
    RAISE EXCEPTION 'Missionaries cannot approve settled-short outcomes.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT is_financial_director AND NOT (
    owns_disbursement
    AND private.has_permission('financial.disbursements.own_confirm')
  ) THEN
    RAISE EXCEPTION 'Disbursement update is outside the authorized workflow.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_disbursement_write_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.disbursements
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_guard_disbursement_write();

ALTER TABLE public.expense_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disbursement_resolutions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS expense_lines_stage3_read ON public.expense_lines;
CREATE POLICY expense_lines_stage3_read ON public.expense_lines
  FOR SELECT TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND (
      (SELECT private.has_permission('financial.read'))
      OR EXISTS (
        SELECT 1
        FROM public.expenses AS expense
        WHERE expense.id = expense_lines.expense_id
          AND private.has_permission('financial.expenses.own_manage')
          AND private.finance_owns_missionary(expense.missionary_id)
      )
    )
  );

DROP POLICY IF EXISTS expense_lines_stage3_insert ON public.expense_lines;
CREATE POLICY expense_lines_stage3_insert ON public.expense_lines
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.is_active_user())
    AND EXISTS (
      SELECT 1
      FROM public.expenses AS expense
      WHERE expense.id = expense_lines.expense_id
        AND expense.status IN ('draft', 'queried')
        AND (
          (SELECT private.has_permission('financial.expenses.own_manage'))
          AND private.finance_owns_missionary(expense.missionary_id)
        )
    )
  );

DROP POLICY IF EXISTS expense_lines_stage3_update ON public.expense_lines;
CREATE POLICY expense_lines_stage3_update ON public.expense_lines
  FOR UPDATE TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND EXISTS (
      SELECT 1 FROM public.expenses AS expense
      WHERE expense.id = expense_lines.expense_id
        AND expense.status IN ('draft', 'queried')
        AND (
          (SELECT private.has_permission('financial.expenses.own_manage'))
          AND private.finance_owns_missionary(expense.missionary_id)
        )
    )
  )
  WITH CHECK (
    (SELECT private.is_active_user())
    AND EXISTS (
      SELECT 1 FROM public.expenses AS expense
      WHERE expense.id = expense_lines.expense_id
        AND expense.status IN ('draft', 'queried')
        AND (
          (SELECT private.has_permission('financial.expenses.own_manage'))
          AND private.finance_owns_missionary(expense.missionary_id)
        )
    )
  );

DROP POLICY IF EXISTS expense_lines_stage3_delete ON public.expense_lines;
CREATE POLICY expense_lines_stage3_delete ON public.expense_lines
  FOR DELETE TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND EXISTS (
      SELECT 1 FROM public.expenses AS expense
      WHERE expense.id = expense_lines.expense_id
        AND expense.status IN ('draft', 'queried')
        AND (
          (SELECT private.has_permission('financial.expenses.own_manage'))
          AND private.finance_owns_missionary(expense.missionary_id)
        )
    )
  );

DROP POLICY IF EXISTS expenses_stage3_own_update ON public.expenses;
CREATE POLICY expenses_stage3_own_update ON public.expenses
  FOR UPDATE TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND status IN ('draft', 'queried')
    AND (SELECT private.has_permission('financial.expenses.own_manage'))
    AND private.finance_owns_missionary(missionary_id)
  )
  WITH CHECK (
    (SELECT private.is_active_user())
    AND status IN ('draft', 'queried')
    AND (SELECT private.has_permission('financial.expenses.own_manage'))
    AND private.finance_owns_missionary(missionary_id)
  );

DROP POLICY IF EXISTS disbursements_stage3_office_read ON public.disbursements;
CREATE POLICY disbursements_stage3_office_read ON public.disbursements
  FOR SELECT TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND (SELECT private.has_permission('financial.disbursements.create'))
    AND created_by = (SELECT auth.uid())
  );

DROP POLICY IF EXISTS expense_receipts_stage3_insert ON public.expense_receipts;
CREATE POLICY expense_receipts_stage3_insert ON public.expense_receipts
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.is_active_user())
    AND EXISTS (
      SELECT 1 FROM public.expenses AS expense
      WHERE expense.id = expense_receipts.expense_id
        AND expense.status IN ('draft', 'queried')
        AND (
          (SELECT private.has_permission('financial.expenses.own_manage'))
          AND private.finance_owns_missionary(expense.missionary_id)
        )
    )
  );

DROP POLICY IF EXISTS disbursement_receipts_stage3_insert ON public.disbursement_receipts;
CREATE POLICY disbursement_receipts_stage3_insert ON public.disbursement_receipts
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.is_active_user())
    AND EXISTS (
      SELECT 1 FROM public.disbursements AS disbursement
      WHERE disbursement.id = disbursement_receipts.disbursement_id
        AND (
          (SELECT private.has_permission('financial.disbursements.evidence'))
          AND disbursement.created_by = (SELECT auth.uid())
        )
    )
  );

DROP POLICY IF EXISTS disbursement_receipts_stage3_read ON public.disbursement_receipts;
CREATE POLICY disbursement_receipts_stage3_read ON public.disbursement_receipts
  FOR SELECT TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND (
      (SELECT private.has_permission('financial.read'))
      OR (
        (SELECT private.has_permission('financial.disbursements.evidence'))
        AND uploaded_by = (SELECT auth.uid())
      )
      OR EXISTS (
        SELECT 1
        FROM public.disbursements AS disbursement
        WHERE disbursement.id = disbursement_receipts.disbursement_id
          AND (SELECT private.has_permission('financial.disbursements.own_confirm'))
          AND private.finance_owns_missionary(disbursement.missionary_id)
      )
    )
  );

DROP POLICY IF EXISTS financial_adjustments_stage3_own_read ON public.financial_adjustments;
CREATE POLICY financial_adjustments_stage3_own_read ON public.financial_adjustments
  FOR SELECT TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND (
      (
        (SELECT private.has_permission('financial.expenses.own_manage'))
        OR (SELECT private.has_permission('financial.disbursements.own_confirm'))
      )
      AND private.finance_owns_missionary(missionary_id)
    )
  );

DROP POLICY IF EXISTS expense_reviews_stage3_own_read ON public.expense_reviews;
CREATE POLICY expense_reviews_stage3_own_read ON public.expense_reviews
  FOR SELECT TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND EXISTS (
      SELECT 1
      FROM public.expenses AS expense
      WHERE expense.id = expense_reviews.expense_id
        AND (
          (SELECT private.has_permission('financial.read'))
          OR (
            (SELECT private.has_permission('financial.expenses.own_manage'))
            AND private.finance_owns_missionary(expense.missionary_id)
          )
        )
    )
  );

DROP POLICY IF EXISTS disbursement_resolutions_stage3_read ON public.disbursement_resolutions;
CREATE POLICY disbursement_resolutions_stage3_read ON public.disbursement_resolutions
  FOR SELECT TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND (
      (SELECT private.has_permission('financial.read'))
      OR EXISTS (
        SELECT 1
        FROM public.disbursements AS disbursement
        WHERE disbursement.id = disbursement_resolutions.disbursement_id
          AND (SELECT private.has_permission('financial.disbursements.own_confirm'))
          AND private.finance_owns_missionary(disbursement.missionary_id)
      )
    )
  );

DROP POLICY IF EXISTS file_assets_stage3_finance_read ON public.file_assets;
CREATE POLICY file_assets_stage3_finance_read ON public.file_assets
  FOR SELECT TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND (
      EXISTS (
        SELECT 1 FROM public.expense_receipts AS receipt
        WHERE receipt.file_asset_id = file_assets.id
      )
      OR EXISTS (
        SELECT 1 FROM public.disbursement_receipts AS receipt
        WHERE receipt.file_asset_id = file_assets.id
      )
    )
    AND (
      uploaded_by = (SELECT auth.uid())
      OR (SELECT private.has_permission('financial.read'))
    )
  );

DROP POLICY IF EXISTS audit_logs_stage3_finance_read ON public.audit_logs;
CREATE POLICY audit_logs_stage3_finance_read ON public.audit_logs
  FOR SELECT TO authenticated
  USING (
    (SELECT private.is_active_user())
    AND (SELECT private.has_permission('financial.read'))
    AND entity_type LIKE 'finance.%'
  );

REVOKE ALL ON TABLE public.expense_lines FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.expense_lines TO authenticated;
REVOKE ALL ON TABLE public.disbursement_resolutions FROM anon, authenticated;
GRANT SELECT ON TABLE public.disbursement_resolutions TO authenticated;

GRANT UPDATE (
  reporting_period_id,
  expense_date,
  currency,
  exchange_rate_to_ghs,
  exchange_rate_date,
  exchange_rate_source,
  description
) ON TABLE public.expenses TO authenticated;
GRANT INSERT ON TABLE public.expense_receipts TO authenticated;
GRANT INSERT ON TABLE public.disbursement_receipts TO authenticated;

CREATE OR REPLACE FUNCTION private.finance_amount_ghs(
  p_amount numeric,
  p_currency character(3),
  p_exchange_rate numeric
)
RETURNS numeric(14,2)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $function$
BEGIN
  IF p_currency = 'GHS' THEN
    RETURN round(p_amount, 2)::numeric(14,2);
  END IF;
  IF p_exchange_rate IS NULL OR p_exchange_rate <= 0 THEN
    RAISE EXCEPTION 'A sourced exchange rate is required for non-GHS reporting.'
      USING ERRCODE = '23514';
  END IF;
  RETURN round(p_amount * p_exchange_rate, 2)::numeric(14,2);
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_confirmed_received_net_ghs(
  p_missionary_id uuid,
  p_reporting_period_id uuid
)
RETURNS numeric(14,2)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  total_ghs numeric(14,2);
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.disbursements AS disbursement
    WHERE disbursement.missionary_id = p_missionary_id
      AND disbursement.reporting_period_id = p_reporting_period_id
      AND disbursement.status IN ('partially_confirmed', 'confirmed', 'settled_short')
      AND disbursement.currency <> 'GHS'
      AND disbursement.exchange_rate_to_ghs IS NULL
  ) THEN
    RAISE EXCEPTION 'A non-GHS disbursement is missing its recorded exchange rate.'
      USING ERRCODE = '23514';
  END IF;

  SELECT coalesce(
    sum(private.finance_amount_ghs(
      coalesce(disbursement.effective_amount_received, disbursement.amount_received),
      disbursement.currency,
      disbursement.exchange_rate_to_ghs
    )),
    0
  )::numeric(14,2)
  INTO total_ghs
  FROM public.disbursements AS disbursement
  WHERE disbursement.missionary_id = p_missionary_id
    AND disbursement.reporting_period_id = p_reporting_period_id
    AND disbursement.status IN ('partially_confirmed', 'confirmed', 'settled_short');

  RETURN coalesce(total_ghs, 0)::numeric(14,2);
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_approved_expenses_ghs(
  p_missionary_id uuid,
  p_reporting_period_id uuid
)
RETURNS numeric(14,2)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  total_ghs numeric(14,2);
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.expenses AS expense
    WHERE expense.missionary_id = p_missionary_id
      AND expense.reporting_period_id = p_reporting_period_id
      AND expense.status = 'approved'
      AND expense.currency <> 'GHS'
      AND expense.exchange_rate_to_ghs IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM public.financial_adjustments AS adjustment
    WHERE adjustment.missionary_id = p_missionary_id
      AND adjustment.reporting_period_id = p_reporting_period_id
      AND adjustment.status = 'approved'
      AND adjustment.expense_id IS NOT NULL
      AND adjustment.adjustment_type NOT IN ('reimbursement', 'carry_forward')
      AND NOT EXISTS (
        SELECT 1
        FROM public.financial_adjustments AS original
        WHERE original.id = adjustment.reversal_of_id
          AND original.adjustment_type IN ('reimbursement', 'carry_forward')
      )
      AND adjustment.currency <> 'GHS'
      AND adjustment.exchange_rate_to_ghs IS NULL
  ) THEN
    RAISE EXCEPTION 'An approved non-GHS expense or adjustment is missing its recorded exchange rate.'
      USING ERRCODE = '23514';
  END IF;

  SELECT coalesce(sum(component.amount_ghs), 0)::numeric(14,2)
  INTO total_ghs
  FROM (
    SELECT private.finance_amount_ghs(
      expense.amount,
      expense.currency,
      expense.exchange_rate_to_ghs
    ) AS amount_ghs
    FROM public.expenses AS expense
    WHERE expense.missionary_id = p_missionary_id
      AND expense.reporting_period_id = p_reporting_period_id
      AND expense.status = 'approved'
    UNION ALL
    SELECT private.finance_amount_ghs(
      adjustment.amount,
      adjustment.currency,
      adjustment.exchange_rate_to_ghs
    ) AS amount_ghs
    FROM public.financial_adjustments AS adjustment
    WHERE adjustment.missionary_id = p_missionary_id
      AND adjustment.reporting_period_id = p_reporting_period_id
      AND adjustment.status = 'approved'
      AND adjustment.expense_id IS NOT NULL
      AND adjustment.adjustment_type NOT IN ('reimbursement', 'carry_forward')
      AND NOT EXISTS (
        SELECT 1
        FROM public.financial_adjustments AS original
        WHERE original.id = adjustment.reversal_of_id
          AND original.adjustment_type IN ('reimbursement', 'carry_forward')
      )
  ) AS component;

  RETURN coalesce(total_ghs, 0)::numeric(14,2);
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_carry_forward_ghs(
  p_missionary_id uuid,
  p_reporting_period_id uuid
)
RETURNS numeric(14,2)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  total_ghs numeric(14,2);
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.financial_adjustments AS adjustment
    WHERE adjustment.missionary_id = p_missionary_id
      AND adjustment.reporting_period_id = p_reporting_period_id
      AND adjustment.adjustment_type = 'carry_forward'
      AND adjustment.status = 'approved'
      AND adjustment.currency <> 'GHS'
      AND adjustment.exchange_rate_to_ghs IS NULL
  ) THEN
    RAISE EXCEPTION 'A non-GHS carry-forward is missing its recorded exchange rate.'
      USING ERRCODE = '23514';
  END IF;

  SELECT coalesce(sum(private.finance_amount_ghs(
    adjustment.amount,
    adjustment.currency,
    adjustment.exchange_rate_to_ghs
  )), 0)::numeric(14,2)
  INTO total_ghs
  FROM public.financial_adjustments AS adjustment
  WHERE adjustment.missionary_id = p_missionary_id
    AND adjustment.reporting_period_id = p_reporting_period_id
    AND adjustment.status = 'approved'
    AND (
      adjustment.adjustment_type = 'carry_forward'
      OR (
        adjustment.adjustment_type = 'reversal'
        AND EXISTS (
          SELECT 1
          FROM public.financial_adjustments AS original
          WHERE original.id = adjustment.reversal_of_id
            AND original.adjustment_type = 'carry_forward'
        )
      )
    );

  RETURN coalesce(total_ghs, 0)::numeric(14,2);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_financial_period_balance(
  p_missionary_id uuid,
  p_reporting_period_id uuid
)
RETURNS TABLE (
  confirmed_received_net_ghs numeric(14,2),
  approved_expenses_ghs numeric(14,2),
  carry_forward_ghs numeric(14,2),
  available_balance_ghs numeric(14,2),
  reimbursement_due_ghs numeric(14,2)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  period_year integer;
BEGIN
  IF NOT private.is_active_user()
     OR NOT (
       private.has_permission('financial.read')
       OR (
         (
           private.has_permission('financial.expenses.own_manage')
           OR private.has_permission('financial.disbursements.own_confirm')
         )
         AND private.finance_owns_missionary(p_missionary_id)
       )
     ) THEN
    RAISE EXCEPTION 'Not authorized to read this financial balance.'
      USING ERRCODE = '42501';
  END IF;

  SELECT year INTO period_year
  FROM public.reporting_periods
  WHERE id = p_reporting_period_id;
  IF NOT FOUND OR period_year < 2027 THEN
    RAISE EXCEPTION 'A 2027+ reporting period is required.'
      USING ERRCODE = '23514';
  END IF;

  confirmed_received_net_ghs :=
    private.finance_confirmed_received_net_ghs(p_missionary_id, p_reporting_period_id);
  approved_expenses_ghs :=
    private.finance_approved_expenses_ghs(p_missionary_id, p_reporting_period_id);
  carry_forward_ghs :=
    private.finance_carry_forward_ghs(p_missionary_id, p_reporting_period_id);
  available_balance_ghs :=
    round(confirmed_received_net_ghs + carry_forward_ghs - approved_expenses_ghs, 2)::numeric(14,2);
  reimbursement_due_ghs :=
    greatest(0, round(approved_expenses_ghs - confirmed_received_net_ghs, 2))::numeric(14,2);
  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_own_financial_expense(
  p_reporting_period_id uuid,
  p_expense_date date,
  p_currency character(3),
  p_exchange_rate_to_ghs numeric,
  p_exchange_rate_date date,
  p_exchange_rate_source text,
  p_description text,
  p_lines jsonb,
  p_client_submission_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  v_missionary_id uuid;
  existing_id uuid;
  existing_payload jsonb;
  canonical_lines jsonb;
  canonical_payload jsonb;
  total_amount numeric(14,2);
  line_count bigint;
  category_count bigint;
  summary_category_id uuid;
  created_expense_id uuid;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.expenses.own_manage') THEN
    RAISE EXCEPTION 'Not authorized to create an expense.'
      USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_missionary_id
  FROM public.missionaries
  WHERE app_user_id = actor_id
    AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active missionary profile is linked to this user.'
      USING ERRCODE = '42501';
  END IF;

  IF p_client_submission_id IS NULL
     OR p_lines IS NULL
     OR jsonb_typeof(p_lines) <> 'array'
     OR jsonb_array_length(p_lines) = 0
     OR nullif(btrim(p_description), '') IS NULL THEN
    RAISE EXCEPTION 'An idempotency key, description, and at least one item line are required.'
      USING ERRCODE = '23514';
  END IF;

  PERFORM private.finance_validate_period_date(p_reporting_period_id, p_expense_date);
  PERFORM private.finance_validate_fx(
    p_currency,
    p_exchange_rate_to_ghs,
    p_exchange_rate_date,
    p_exchange_rate_source
  );

  SELECT
    count(*),
    coalesce(sum(line.amount), 0)::numeric(14,2),
    count(DISTINCT line.expense_category_id),
    jsonb_agg(
      jsonb_build_object(
        'line_number', line.line_number,
        'expense_category_id', line.expense_category_id,
        'description', btrim(line.description),
        'amount', line.amount
      )
      ORDER BY line.line_number
    )
  INTO line_count, total_amount, category_count, canonical_lines
  FROM jsonb_to_recordset(p_lines) AS line(
    line_number integer,
    expense_category_id uuid,
    description text,
    amount numeric
  );

  IF line_count <> jsonb_array_length(p_lines)
     OR EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(p_lines) AS line(
         line_number integer,
         expense_category_id uuid,
         description text,
         amount numeric
       )
       WHERE line.line_number IS NULL
          OR line.line_number <= 0
          OR line.expense_category_id IS NULL
          OR line.amount IS NULL
          OR line.amount <= 0
          OR line.amount <> round(line.amount, 2)
          OR nullif(btrim(line.description), '') IS NULL
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(p_lines) AS line(
         line_number integer,
         expense_category_id uuid,
         description text,
         amount numeric
       )
       LEFT JOIN public.expense_categories AS category
         ON category.id = line.expense_category_id
       WHERE category.id IS NULL
          OR NOT category.is_active
          OR category.code NOT IN (
            'fuel',
            'vehicle_servicing_maintenance',
            'vehicle_parts_repairs',
            'engine_oil_lubricants',
            'travel_transport_general',
            'field_outreach_ministry',
            'supplies_materials',
            'communication_data',
            'accommodation_meals',
            'admin_banking_fees',
            'miscellaneous_other'
          )
     )
     OR EXISTS (
       SELECT 1
       FROM jsonb_to_recordset(p_lines) AS line(
         line_number integer,
         expense_category_id uuid,
         description text,
         amount numeric
       )
       GROUP BY line.line_number
       HAVING count(*) > 1
     )
     OR total_amount <= 0 THEN
    RAISE EXCEPTION 'Expense lines contain invalid or unapproved data.'
      USING ERRCODE = '23514';
  END IF;

  IF category_count = 1 THEN
    SELECT line.expense_category_id INTO summary_category_id
    FROM jsonb_to_recordset(p_lines) AS line(
      line_number integer,
      expense_category_id uuid,
      description text,
      amount numeric
    )
    ORDER BY line.line_number
    LIMIT 1;
  END IF;

  canonical_payload := jsonb_build_object(
    'reporting_period_id', p_reporting_period_id,
    'expense_date', p_expense_date,
    'currency', p_currency,
    'exchange_rate_to_ghs', p_exchange_rate_to_ghs,
    'exchange_rate_date', p_exchange_rate_date,
    'exchange_rate_source', p_exchange_rate_source,
    'description', btrim(p_description),
    'lines', canonical_lines
  );

  SELECT id, submission_payload
  INTO existing_id, existing_payload
  FROM public.expenses
  WHERE expenses.missionary_id = v_missionary_id
    AND expenses.client_submission_id = p_client_submission_id;

  IF FOUND THEN
    IF existing_payload IS DISTINCT FROM canonical_payload THEN
      RAISE EXCEPTION 'The expense idempotency key was reused with a different payload.'
        USING ERRCODE = '23505';
    END IF;
    RETURN existing_id;
  END IF;

  INSERT INTO public.expenses (
    missionary_id,
    reporting_period_id,
    expense_category_id,
    expense_date,
    amount,
    currency,
    exchange_rate_to_ghs,
    exchange_rate_date,
    exchange_rate_source,
    description,
    status,
    created_by,
    client_submission_id,
    submission_payload
  )
  VALUES (
    v_missionary_id,
    p_reporting_period_id,
    summary_category_id,
    p_expense_date,
    total_amount,
    p_currency,
    p_exchange_rate_to_ghs,
    p_exchange_rate_date,
    p_exchange_rate_source,
    btrim(p_description),
    'draft',
    actor_id,
    p_client_submission_id,
    canonical_payload
  )
  RETURNING id INTO created_expense_id;

  INSERT INTO public.expense_lines (
    expense_id,
    expense_category_id,
    line_number,
    description,
    amount
  )
  SELECT
    created_expense_id,
    line.expense_category_id,
    line.line_number,
    btrim(line.description),
    line.amount::numeric(14,2)
  FROM jsonb_to_recordset(p_lines) AS line(
    line_number integer,
    expense_category_id uuid,
    description text,
    amount numeric
  )
  ORDER BY line.line_number;

  RETURN created_expense_id;
EXCEPTION
  WHEN unique_violation THEN
    SELECT id, submission_payload
    INTO existing_id, existing_payload
    FROM public.expenses
    WHERE expenses.missionary_id = v_missionary_id
      AND expenses.client_submission_id = p_client_submission_id;
    IF FOUND AND existing_payload = canonical_payload THEN
      RETURN existing_id;
    END IF;
    RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_own_financial_expense(
  p_expense_id uuid,
  p_over_funds_note text DEFAULT NULL
)
RETURNS public.expenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  expense_row public.expenses%ROWTYPE;
  active_receipts bigint;
  line_total numeric(14,2);
  approved_total_ghs numeric(14,2);
  received_total_ghs numeric(14,2);
  proposed_total_ghs numeric(14,2);
  exceeds_confirmed boolean;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.expenses.own_manage') THEN
    RAISE EXCEPTION 'Not authorized to submit this expense.'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO expense_row
  FROM public.expenses
  WHERE id = p_expense_id
  FOR UPDATE;

  IF NOT FOUND
     OR NOT private.finance_owns_missionary(expense_row.missionary_id) THEN
    RAISE EXCEPTION 'Expense not found or not owned by the active missionary.'
      USING ERRCODE = '42501';
  END IF;

  PERFORM private.finance_period_lock(expense_row.reporting_period_id);

  IF expense_row.status NOT IN ('draft', 'queried') THEN
    RAISE EXCEPTION 'Only draft or queried expenses can be submitted.'
      USING ERRCODE = '23514';
  END IF;

  SELECT count(*)
  INTO active_receipts
  FROM (
    SELECT receipt.id
    FROM public.expense_receipts AS receipt
    WHERE receipt.expense_id = expense_row.id
      AND NOT EXISTS (
        SELECT 1
        FROM public.expense_receipts AS replacement
        WHERE replacement.supersedes_receipt_id = receipt.id
      )
  ) AS active_receipt_rows;

  SELECT coalesce(sum(line.amount), 0)::numeric(14,2)
  INTO line_total
  FROM public.expense_lines AS line
  WHERE line.expense_id = expense_row.id;

  IF active_receipts < 1 OR line_total <> expense_row.amount THEN
    RAISE EXCEPTION 'A submitted expense requires at least one active receipt and an exact item-line total.'
      USING ERRCODE = '23514';
  END IF;

  PERFORM private.finance_validate_period_date(
    expense_row.reporting_period_id,
    expense_row.expense_date
  );
  PERFORM private.finance_validate_fx(
    expense_row.currency,
    expense_row.exchange_rate_to_ghs,
    expense_row.exchange_rate_date,
    expense_row.exchange_rate_source
  );

  approved_total_ghs := private.finance_approved_expenses_ghs(
    expense_row.missionary_id,
    expense_row.reporting_period_id
  );
  received_total_ghs := private.finance_confirmed_received_net_ghs(
    expense_row.missionary_id,
    expense_row.reporting_period_id
  );
  proposed_total_ghs := round(
    approved_total_ghs
    + private.finance_amount_ghs(
      expense_row.amount,
      expense_row.currency,
      expense_row.exchange_rate_to_ghs
    ),
    2
  )::numeric(14,2);
  exceeds_confirmed := proposed_total_ghs > received_total_ghs;

  IF exceeds_confirmed AND nullif(btrim(p_over_funds_note), '') IS NULL THEN
    RAISE EXCEPTION 'Expenses above confirmed received funds require a note.'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.expenses
  SET status = 'submitted',
      submitted_at = now(),
      over_funds_flag = exceeds_confirmed,
      over_funds_note = CASE WHEN exceeds_confirmed THEN btrim(p_over_funds_note) ELSE NULL END,
      updated_at = now()
  WHERE id = expense_row.id
  RETURNING * INTO expense_row;

  RETURN expense_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_own_financial_expense(p_expense_id uuid)
RETURNS public.expenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  expense_row public.expenses%ROWTYPE;
BEGIN
  IF NOT private.is_active_user()
     OR NOT private.has_permission('financial.expenses.own_manage') THEN
    RAISE EXCEPTION 'Not authorized to cancel this expense.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO expense_row
  FROM public.expenses
  WHERE id = p_expense_id
  FOR UPDATE;

  IF NOT FOUND OR NOT private.finance_owns_missionary(expense_row.missionary_id) THEN
    RAISE EXCEPTION 'Expense not found or not owned by the active missionary.'
      USING ERRCODE = '42501';
  END IF;
  IF expense_row.status NOT IN ('draft', 'submitted', 'queried') THEN
    RAISE EXCEPTION 'Only unapproved expenses may be cancelled.'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.expenses
  SET status = 'cancelled', updated_at = now()
  WHERE id = expense_row.id
  RETURNING * INTO expense_row;
  RETURN expense_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.review_financial_expense(
  p_expense_id uuid,
  p_decision text,
  p_comments text DEFAULT NULL
)
RETURNS public.expenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  expense_row public.expenses%ROWTYPE;
  next_status text;
  decision_code text;
  line_total numeric(14,2);
  receipt_count bigint;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.manage') THEN
    RAISE EXCEPTION 'Only an active Financial Director may review expenses.'
      USING ERRCODE = '42501';
  END IF;

  IF p_decision IS NULL
     OR p_decision NOT IN ('approve', 'query', 'reject')
     OR (p_decision <> 'approve' AND nullif(btrim(p_comments), '') IS NULL) THEN
    RAISE EXCEPTION 'Decision must be approve, query, or reject; query/reject requires comments.'
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO expense_row
  FROM public.expenses
  WHERE id = p_expense_id
  FOR UPDATE;

  IF NOT FOUND OR expense_row.status <> 'submitted' THEN
    RAISE EXCEPTION 'Only submitted expenses may be reviewed.'
      USING ERRCODE = '23514';
  END IF;

  PERFORM private.finance_period_lock(expense_row.reporting_period_id);

  IF expense_row.created_by = actor_id
     OR EXISTS (
       SELECT 1
       FROM public.missionaries AS missionary
       WHERE missionary.id = expense_row.missionary_id
         AND missionary.app_user_id = actor_id
     ) THEN
    RAISE EXCEPTION 'A reviewer cannot approve, query, or reject their own expense.'
      USING ERRCODE = '42501';
  END IF;

  SELECT coalesce(sum(line.amount), 0)::numeric(14,2)
  INTO line_total
  FROM public.expense_lines AS line
  WHERE line.expense_id = expense_row.id;
  SELECT count(*)
  INTO receipt_count
  FROM public.expense_receipts AS receipt
  WHERE receipt.expense_id = expense_row.id
    AND NOT EXISTS (
      SELECT 1 FROM public.expense_receipts AS replacement
      WHERE replacement.supersedes_receipt_id = receipt.id
    );

  IF line_total <> expense_row.amount OR receipt_count < 1 THEN
    RAISE EXCEPTION 'Expense line total or active receipt requirement is not satisfied.'
      USING ERRCODE = '23514';
  END IF;

  PERFORM private.finance_validate_period_date(
    expense_row.reporting_period_id,
    expense_row.expense_date
  );
  PERFORM private.finance_validate_fx(
    expense_row.currency,
    expense_row.exchange_rate_to_ghs,
    expense_row.exchange_rate_date,
    expense_row.exchange_rate_source
  );

  next_status := CASE p_decision
    WHEN 'approve' THEN 'approved'
    WHEN 'query' THEN 'queried'
    ELSE 'rejected'
  END;
  decision_code := CASE p_decision
    WHEN 'approve' THEN 'approve'
    WHEN 'query' THEN 'request_clarification'
    ELSE 'reject'
  END;

  UPDATE public.expenses
  SET status = next_status, updated_at = now()
  WHERE id = expense_row.id
  RETURNING * INTO expense_row;

  INSERT INTO public.expense_reviews (
    expense_id, reviewer_id, decision, comments, previous_status, new_status
  )
  VALUES (
    expense_row.id,
    actor_id,
    decision_code,
    nullif(btrim(p_comments), ''),
    'submitted',
    next_status
  );

  RETURN expense_row;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_disbursement_effective_native(
  p_disbursement_id uuid,
  p_raw_received numeric
)
RETURNS numeric(14,2)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT (
    coalesce(p_raw_received, 0)
    + coalesce(sum(adjustment.amount), 0)
  )::numeric(14,2)
  FROM public.financial_adjustments AS adjustment
  WHERE adjustment.disbursement_id = p_disbursement_id
    AND adjustment.status = 'approved'
    AND adjustment.adjustment_type NOT IN ('carry_forward', 'reimbursement')
    AND NOT EXISTS (
      SELECT 1
      FROM public.financial_adjustments AS original
      WHERE original.id = adjustment.reversal_of_id
        AND original.adjustment_type IN ('carry_forward', 'reimbursement')
    );
$function$;

CREATE OR REPLACE FUNCTION private.finance_refresh_disbursement_status(
  p_disbursement_id uuid,
  p_resolve_dispute boolean DEFAULT false
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  disbursement_row public.disbursements%ROWTYPE;
  effective_amount numeric(14,2);
  next_status text;
BEGIN
  SELECT * INTO disbursement_row
  FROM public.disbursements
  WHERE id = p_disbursement_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Disbursement not found.' USING ERRCODE = '23503';
  END IF;

  IF disbursement_row.status = 'cancelled'
     OR (disbursement_row.status = 'disputed' AND NOT p_resolve_dispute) THEN
    RETURN disbursement_row.status;
  END IF;

  effective_amount := private.finance_disbursement_effective_native(
    disbursement_row.id,
    disbursement_row.amount_received
  );
  IF effective_amount < 0 THEN
    RAISE EXCEPTION 'Approved adjustments cannot make received funds negative.'
      USING ERRCODE = '23514';
  END IF;

  IF disbursement_row.status = 'reconciliation_required' AND NOT p_resolve_dispute THEN
    UPDATE public.disbursements
    SET effective_amount_received = effective_amount,
        updated_at = now()
    WHERE id = disbursement_row.id;
    RETURN disbursement_row.status;
  END IF;

  IF disbursement_row.status = 'settled_short' THEN
    IF effective_amount = disbursement_row.amount_sent THEN
      next_status := 'confirmed';
    ELSIF effective_amount > disbursement_row.amount_sent THEN
      next_status := 'reconciliation_required';
    ELSE
      UPDATE public.disbursements
      SET effective_amount_received = effective_amount,
          updated_at = now()
      WHERE id = disbursement_row.id;
      RETURN 'settled_short';
    END IF;
    UPDATE public.disbursements
    SET effective_amount_received = effective_amount,
        status = next_status,
        updated_at = now()
    WHERE id = disbursement_row.id;
    RETURN next_status;
  END IF;

  IF effective_amount = disbursement_row.amount_sent THEN
    next_status := 'confirmed';
  ELSIF effective_amount > disbursement_row.amount_sent THEN
    next_status := 'reconciliation_required';
  ELSIF effective_amount > 0 THEN
    next_status := 'partially_confirmed';
  ELSE
    next_status := 'awaiting_confirmation';
  END IF;

  UPDATE public.disbursements
  SET effective_amount_received = effective_amount,
      status = next_status,
      updated_at = now()
  WHERE id = disbursement_row.id;

  RETURN next_status;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_financial_disbursement(
  p_reference text,
  p_missionary_id uuid,
  p_reporting_period_id uuid,
  p_amount_sent numeric,
  p_currency character(3),
  p_sent_date date,
  p_payment_method text,
  p_transaction_reference text,
  p_notes text,
  p_exchange_rate_to_ghs numeric,
  p_exchange_rate_date date,
  p_exchange_rate_source text,
  p_client_submission_id uuid
)
RETURNS public.disbursements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  created_disbursement public.disbursements%ROWTYPE;
  existing_disbursement public.disbursements%ROWTYPE;
  request_body jsonb;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.disbursements.create') THEN
    RAISE EXCEPTION 'Not authorized to create a disbursement.'
      USING ERRCODE = '42501';
  END IF;

  IF p_client_submission_id IS NULL THEN
    RAISE EXCEPTION 'A disbursement idempotency key is required.'
      USING ERRCODE = '23514';
  END IF;
  request_body := jsonb_build_object(
    'reference', nullif(btrim(p_reference), ''),
    'missionary_id', p_missionary_id,
    'reporting_period_id', p_reporting_period_id,
    'amount_sent', p_amount_sent,
    'currency', p_currency,
    'sent_date', p_sent_date,
    'payment_method', nullif(btrim(p_payment_method), ''),
    'transaction_reference', nullif(btrim(p_transaction_reference), ''),
    'notes', nullif(btrim(p_notes), ''),
    'exchange_rate_to_ghs', p_exchange_rate_to_ghs,
    'exchange_rate_date', p_exchange_rate_date,
    'exchange_rate_source', p_exchange_rate_source
  );
  SELECT * INTO existing_disbursement
  FROM public.disbursements
  WHERE created_by = actor_id
    AND client_submission_id = p_client_submission_id;
  IF FOUND THEN
    IF existing_disbursement.submission_payload IS DISTINCT FROM request_body THEN
      RAISE EXCEPTION 'The disbursement idempotency key was reused with a different payload.'
        USING ERRCODE = '23505';
    END IF;
    RETURN existing_disbursement;
  END IF;

  IF nullif(btrim(p_reference), '') IS NULL
     OR nullif(btrim(p_payment_method), '') IS NULL
     OR p_amount_sent IS NULL
     OR p_amount_sent <= 0
     OR p_amount_sent <> round(p_amount_sent, 2) THEN
    RAISE EXCEPTION 'Reference, payment method, and a positive two-decimal amount are required.'
      USING ERRCODE = '23514';
  END IF;

  PERFORM private.finance_validate_period_date(p_reporting_period_id, p_sent_date);
  PERFORM private.finance_validate_fx(
    p_currency,
    p_exchange_rate_to_ghs,
    p_exchange_rate_date,
    p_exchange_rate_source
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.missionaries
    WHERE id = p_missionary_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'An active missionary is required.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.disbursements (
    reference,
    missionary_id,
    reporting_period_id,
    amount_sent,
    currency,
    sent_date,
    payment_method,
    transaction_reference,
    status,
    amount_received,
    effective_amount_received,
    exchange_rate_to_ghs,
    exchange_rate_date,
    exchange_rate_source,
    notes,
    created_by,
    client_submission_id,
    submission_payload
  )
  VALUES (
    btrim(p_reference),
    p_missionary_id,
    p_reporting_period_id,
    p_amount_sent::numeric(14,2),
    p_currency,
    p_sent_date,
    btrim(p_payment_method),
    nullif(btrim(p_transaction_reference), ''),
    'awaiting_confirmation',
    NULL,
    0,
    p_exchange_rate_to_ghs,
    p_exchange_rate_date,
    p_exchange_rate_source,
    nullif(btrim(p_notes), ''),
    actor_id,
    p_client_submission_id,
    request_body
  )
  RETURNING * INTO created_disbursement;

  RETURN created_disbursement;
EXCEPTION
  WHEN unique_violation THEN
    SELECT * INTO existing_disbursement
    FROM public.disbursements
    WHERE created_by = actor_id
      AND client_submission_id = p_client_submission_id;
    IF FOUND AND existing_disbursement.submission_payload = request_body THEN
      RETURN existing_disbursement;
    END IF;
    RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_own_disbursement_confirmation(
  p_disbursement_id uuid,
  p_decision text,
  p_amount_received numeric,
  p_received_date date,
  p_amount_mode text,
  p_notes text,
  p_client_submission_id uuid
)
RETURNS public.disbursement_confirmations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  disbursement_row public.disbursements%ROWTYPE;
  existing_event public.disbursement_confirmations%ROWTYPE;
  created_event public.disbursement_confirmations%ROWTYPE;
  request_body jsonb;
  old_amount numeric(14,2);
  new_amount numeric(14,2);
  effective_amount numeric(14,2);
  next_status text;
  reporting_period_id uuid;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.disbursements.own_confirm') THEN
    RAISE EXCEPTION 'Not authorized to confirm or dispute this disbursement.'
      USING ERRCODE = '42501';
  END IF;

  IF p_client_submission_id IS NULL
     OR p_decision IS NULL
     OR p_decision NOT IN ('confirm', 'dispute') THEN
    RAISE EXCEPTION 'A confirmation key and valid decision are required.'
      USING ERRCODE = '23514';
  END IF;

  request_body := jsonb_build_object(
    'disbursement_id', p_disbursement_id,
    'decision', p_decision,
    'amount_received', p_amount_received,
    'received_date', p_received_date,
    'amount_mode', p_amount_mode,
    'notes', nullif(btrim(p_notes), '')
  );

  SELECT * INTO existing_event
  FROM public.disbursement_confirmations
  WHERE confirmed_by = actor_id
    AND decision = p_decision
    AND client_submission_id = p_client_submission_id;
  IF FOUND THEN
    IF existing_event.request_payload IS DISTINCT FROM request_body THEN
      RAISE EXCEPTION 'The confirmation idempotency key was reused with a different payload.'
        USING ERRCODE = '23505';
    END IF;
    RETURN existing_event;
  END IF;

  SELECT disbursement.reporting_period_id INTO reporting_period_id
  FROM public.disbursements
  AS disbursement
  WHERE disbursement.id = p_disbursement_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Disbursement not found or not assigned to the active missionary.'
      USING ERRCODE = '42501';
  END IF;
  PERFORM private.finance_period_lock(reporting_period_id);
  SELECT * INTO disbursement_row
  FROM public.disbursements
  WHERE id = p_disbursement_id
  FOR UPDATE;
  IF NOT FOUND OR NOT private.finance_owns_missionary(disbursement_row.missionary_id) THEN
    RAISE EXCEPTION 'Disbursement not found or not assigned to the active missionary.'
      USING ERRCODE = '42501';
  END IF;
  IF disbursement_row.status IN ('cancelled', 'settled_short') THEN
    RAISE EXCEPTION 'This disbursement no longer accepts confirmations.'
      USING ERRCODE = '23514';
  END IF;

  IF p_decision = 'dispute' THEN
    IF nullif(btrim(p_notes), '') IS NULL
       OR disbursement_row.status = 'disputed' THEN
      RAISE EXCEPTION 'A new dispute requires notes and cannot duplicate an unresolved dispute.'
        USING ERRCODE = '23514';
    END IF;

    INSERT INTO public.disbursement_confirmations (
      disbursement_id, confirmed_by, decision, notes, client_submission_id, request_payload
    )
    VALUES (
      disbursement_row.id, actor_id, 'dispute', btrim(p_notes),
      p_client_submission_id, request_body
    )
    RETURNING * INTO created_event;

    UPDATE public.disbursements
    SET status = 'disputed',
        confirmation_notes = btrim(p_notes),
        updated_at = now()
    WHERE id = disbursement_row.id;
    RETURN created_event;
  END IF;

  IF p_amount_received IS NULL
     OR p_amount_received <= 0
     OR p_amount_received <> round(p_amount_received, 2)
     OR p_received_date IS NULL
     OR p_amount_mode IS NULL
     OR p_amount_mode NOT IN ('incremental', 'cumulative')
     OR disbursement_row.status IN ('disputed', 'reconciliation_required') THEN
    RAISE EXCEPTION 'A positive amount, date, valid mode, and unresolved-dispute-free state are required.'
      USING ERRCODE = '23514';
  END IF;

  PERFORM private.finance_validate_period_date(
    disbursement_row.reporting_period_id,
    p_received_date
  );

  old_amount := coalesce(disbursement_row.amount_received, 0);
  IF p_amount_mode = 'incremental' THEN
    new_amount := old_amount + p_amount_received;
  ELSE
    IF p_amount_received < old_amount THEN
      RAISE EXCEPTION 'A cumulative confirmation cannot reduce the prior total; request an approved adjustment.'
        USING ERRCODE = '23514';
    END IF;
    new_amount := p_amount_received;
  END IF;

  effective_amount := private.finance_disbursement_effective_native(
    disbursement_row.id,
    new_amount
  );
  IF effective_amount < 0 THEN
    RAISE EXCEPTION 'Confirmed net received amount cannot be negative.'
      USING ERRCODE = '23514';
  END IF;

  IF effective_amount = disbursement_row.amount_sent THEN
    next_status := 'confirmed';
  ELSIF effective_amount > disbursement_row.amount_sent THEN
    next_status := 'reconciliation_required';
  ELSE
    next_status := 'partially_confirmed';
  END IF;

  INSERT INTO public.disbursement_confirmations (
    disbursement_id,
    confirmed_by,
    decision,
    amount_received,
    received_date,
    notes,
    amount_mode,
    client_submission_id,
    request_payload
  )
  VALUES (
    disbursement_row.id,
    actor_id,
    'confirm',
    p_amount_received::numeric(14,2),
    p_received_date,
    nullif(btrim(p_notes), ''),
    p_amount_mode,
    p_client_submission_id,
    request_body
  )
  RETURNING * INTO created_event;

  UPDATE public.disbursements
  SET amount_received = new_amount,
      effective_amount_received = effective_amount,
      received_date = p_received_date,
      confirmation_notes = nullif(btrim(p_notes), ''),
      status = next_status,
      updated_at = now()
  WHERE id = disbursement_row.id;

  RETURN created_event;
EXCEPTION
  WHEN unique_violation THEN
    SELECT * INTO existing_event
    FROM public.disbursement_confirmations
    WHERE confirmed_by = actor_id
      AND decision = p_decision
      AND client_submission_id = p_client_submission_id;
    IF FOUND AND existing_event.request_payload = request_body THEN
      RETURN existing_event;
    END IF;
    RAISE EXCEPTION 'The confirmation idempotency key conflicts with a different committed payload.'
      USING ERRCODE = '23505';
END;
$function$;

CREATE OR REPLACE FUNCTION public.resolve_financial_disbursement(
  p_disbursement_id uuid,
  p_resolution_type text,
  p_notes text,
  p_financial_adjustment_id uuid DEFAULT NULL
)
RETURNS public.disbursement_resolutions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  disbursement_row public.disbursements%ROWTYPE;
  adjustment_row public.financial_adjustments%ROWTYPE;
  previous_state text;
  effective_amount numeric(14,2);
  next_state text;
  resolution public.disbursement_resolutions%ROWTYPE;
  reporting_period_id uuid;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.manage') THEN
    RAISE EXCEPTION 'Only an active Financial Director may resolve a disbursement.'
      USING ERRCODE = '42501';
  END IF;
  IF p_resolution_type IS NULL
     OR p_resolution_type NOT IN ('resolve_dispute', 'settle_short', 'reconcile_overpayment')
     OR nullif(btrim(p_notes), '') IS NULL THEN
    RAISE EXCEPTION 'A valid resolution type and explanatory note are required.'
      USING ERRCODE = '23514';
  END IF;

  SELECT disbursement.reporting_period_id INTO reporting_period_id
  FROM public.disbursements AS disbursement
  WHERE disbursement.id = p_disbursement_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Disbursement not found.' USING ERRCODE = '23503';
  END IF;
  PERFORM private.finance_period_lock(reporting_period_id);
  SELECT * INTO disbursement_row
  FROM public.disbursements
  WHERE id = p_disbursement_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Disbursement not found.' USING ERRCODE = '23503';
  END IF;
  IF disbursement_row.created_by = actor_id THEN
    RAISE EXCEPTION 'The disbursement creator cannot approve its resolution.'
      USING ERRCODE = '42501';
  END IF;
  previous_state := disbursement_row.status;

  effective_amount := private.finance_disbursement_effective_native(
    disbursement_row.id,
    disbursement_row.amount_received
  );

  IF p_resolution_type = 'resolve_dispute' THEN
    IF disbursement_row.status <> 'disputed' THEN
      RAISE EXCEPTION 'Only a disputed disbursement can be cleared.'
        USING ERRCODE = '23514';
    END IF;
    next_state := private.finance_refresh_disbursement_status(disbursement_row.id, true);
    IF next_state = 'disputed' THEN
      RAISE EXCEPTION 'Dispute resolution did not produce a valid disbursement state.'
        USING ERRCODE = '23514';
    END IF;
  ELSIF p_resolution_type = 'settle_short' THEN
    IF disbursement_row.status NOT IN ('partially_confirmed', 'disputed')
       OR effective_amount <= 0
       OR effective_amount >= disbursement_row.amount_sent THEN
      RAISE EXCEPTION 'Settled-short requires a positive net receipt below the amount sent.'
        USING ERRCODE = '23514';
    END IF;
    UPDATE public.disbursements
    SET status = 'settled_short',
        effective_amount_received = effective_amount,
        settlement_note = btrim(p_notes),
        settled_short_approved_by = actor_id,
        settled_short_approved_at = now(),
        updated_at = now()
    WHERE id = disbursement_row.id;
    next_state := 'settled_short';
  ELSE
    IF disbursement_row.status <> 'reconciliation_required'
       OR p_financial_adjustment_id IS NULL THEN
      RAISE EXCEPTION 'Overpayment reconciliation requires a reconciliation-required disbursement and linked adjustment.'
        USING ERRCODE = '23514';
    END IF;
    SELECT * INTO adjustment_row
    FROM public.financial_adjustments
    WHERE id = p_financial_adjustment_id
      AND disbursement_id = disbursement_row.id
      AND status = 'approved'
      AND adjustment_type NOT IN ('carry_forward', 'reimbursement');
    IF NOT FOUND THEN
      RAISE EXCEPTION 'The linked adjustment must be approved and belong to this disbursement.'
        USING ERRCODE = '23514';
    END IF;
    next_state := private.finance_refresh_disbursement_status(disbursement_row.id, true);
    IF next_state <> 'confirmed' THEN
      RAISE EXCEPTION 'The approved adjustment does not reconcile the exact amount sent.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  INSERT INTO public.disbursement_resolutions (
    disbursement_id,
    resolution_type,
    resolved_by,
    notes,
    financial_adjustment_id,
    previous_status,
    new_status
  )
  VALUES (
    disbursement_row.id,
    p_resolution_type,
    actor_id,
    btrim(p_notes),
    p_financial_adjustment_id,
    previous_state,
    next_state
  )
  RETURNING * INTO resolution;

  RETURN resolution;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_financial_adjustment(
  p_reporting_period_id uuid,
  p_disbursement_id uuid,
  p_expense_id uuid,
  p_adjustment_type text,
  p_amount numeric,
  p_currency character(3),
  p_reason text,
  p_adjustment_date date,
  p_exchange_rate_to_ghs numeric,
  p_exchange_rate_date date,
  p_exchange_rate_source text,
  p_client_submission_id uuid,
  p_reversal_of_id uuid DEFAULT NULL
)
RETURNS public.financial_adjustments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  target_missionary_id uuid;
  target_period_id uuid;
  target_currency character(3);
  created_adjustment public.financial_adjustments%ROWTYPE;
  source_period public.reporting_periods%ROWTYPE;
  target_period public.reporting_periods%ROWTYPE;
  previous_adjustment public.financial_adjustments%ROWTYPE;
  existing_adjustment public.financial_adjustments%ROWTYPE;
  request_body jsonb;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.manage') THEN
    RAISE EXCEPTION 'Only an active Financial Director may create financial adjustments.'
      USING ERRCODE = '42501';
  END IF;
  IF p_client_submission_id IS NULL THEN
    RAISE EXCEPTION 'An adjustment idempotency key is required.'
      USING ERRCODE = '23514';
  END IF;
  IF p_adjustment_type IS NULL
     OR p_adjustment_type NOT IN ('correction', 'reimbursement', 'reversal', 'carry_forward', 'other')
     OR p_amount IS NULL
     OR p_amount = 0
     OR p_amount <> round(p_amount, 2)
     OR nullif(btrim(p_reason), '') IS NULL
     OR num_nonnulls(p_disbursement_id, p_expense_id) <> 1 THEN
    RAISE EXCEPTION 'Adjustment type, non-zero two-decimal amount, reason, and exactly one target are required.'
      USING ERRCODE = '23514';
  END IF;

  request_body := jsonb_build_object(
    'reporting_period_id', p_reporting_period_id,
    'disbursement_id', p_disbursement_id,
    'expense_id', p_expense_id,
    'adjustment_type', p_adjustment_type,
    'amount', p_amount,
    'currency', p_currency,
    'reason', nullif(btrim(p_reason), ''),
    'adjustment_date', p_adjustment_date,
    'exchange_rate_to_ghs', p_exchange_rate_to_ghs,
    'exchange_rate_date', p_exchange_rate_date,
    'exchange_rate_source', p_exchange_rate_source,
    'reversal_of_id', p_reversal_of_id
  );
  SELECT * INTO existing_adjustment
  FROM public.financial_adjustments
  WHERE requested_by = actor_id
    AND client_submission_id = p_client_submission_id;
  IF FOUND THEN
    IF existing_adjustment.submission_payload IS DISTINCT FROM request_body THEN
      RAISE EXCEPTION 'The adjustment idempotency key was reused with a different payload.'
        USING ERRCODE = '23505';
    END IF;
    RETURN existing_adjustment;
  END IF;

  PERFORM private.finance_validate_period_date(p_reporting_period_id, p_adjustment_date);
  PERFORM private.finance_validate_fx(
    p_currency,
    p_exchange_rate_to_ghs,
    p_exchange_rate_date,
    p_exchange_rate_source
  );

  IF p_disbursement_id IS NOT NULL THEN
    SELECT disbursement.missionary_id,
           disbursement.reporting_period_id,
           disbursement.currency
    INTO target_missionary_id, target_period_id, target_currency
    FROM public.disbursements AS disbursement
    WHERE disbursement.id = p_disbursement_id
    FOR UPDATE;
  ELSE
    SELECT expense.missionary_id,
           expense.reporting_period_id,
           expense.currency
    INTO target_missionary_id, target_period_id, target_currency
    FROM public.expenses AS expense
    WHERE expense.id = p_expense_id
    FOR UPDATE;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Adjustment target not found.' USING ERRCODE = '23503';
  END IF;

  IF p_adjustment_type = 'carry_forward' THEN
    IF p_disbursement_id IS NULL OR p_expense_id IS NOT NULL THEN
      RAISE EXCEPTION 'Carry-forward must reference a source disbursement.'
        USING ERRCODE = '23514';
    END IF;
    IF p_currency <> target_currency OR p_amount <= 0 THEN
      RAISE EXCEPTION 'Carry-forward must be positive and retain the source currency.'
        USING ERRCODE = '23514';
    END IF;

    SELECT * INTO source_period
    FROM public.reporting_periods
    WHERE id = target_period_id;
    SELECT * INTO target_period
    FROM public.reporting_periods
    WHERE id = p_reporting_period_id;

    IF source_period.year < 2027
       OR target_period.year < 2027
       OR source_period.period_type <> target_period.period_type
       OR target_period.start_date <> source_period.end_date + 1 THEN
      RAISE EXCEPTION 'Carry-forward must target the immediately following 2027+ reporting period.'
        USING ERRCODE = '23514';
    END IF;
  ELSIF p_adjustment_type <> 'reversal' AND p_reporting_period_id <> target_period_id THEN
    RAISE EXCEPTION 'A correction or settlement must use its target transaction reporting period.'
      USING ERRCODE = '23514';
  END IF;

  IF p_adjustment_type <> 'carry_forward' AND p_currency <> target_currency THEN
    RAISE EXCEPTION 'Linked adjustments must retain the target transaction currency.'
      USING ERRCODE = '23514';
  END IF;

  IF p_adjustment_type = 'reversal' THEN
    IF p_reversal_of_id IS NULL THEN
      RAISE EXCEPTION 'A reversal must identify its original adjustment.'
        USING ERRCODE = '23514';
    END IF;

    SELECT * INTO previous_adjustment
    FROM public.financial_adjustments
    WHERE id = p_reversal_of_id
      AND status = 'approved'
    FOR UPDATE;
    IF NOT FOUND
       OR previous_adjustment.reversal_of_id IS NOT NULL
       OR previous_adjustment.amount <> -p_amount
       OR previous_adjustment.currency <> p_currency
       OR previous_adjustment.exchange_rate_to_ghs IS DISTINCT FROM p_exchange_rate_to_ghs
       OR previous_adjustment.exchange_rate_date IS DISTINCT FROM p_exchange_rate_date
       OR previous_adjustment.exchange_rate_source IS DISTINCT FROM p_exchange_rate_source
       OR previous_adjustment.disbursement_id IS DISTINCT FROM p_disbursement_id
       OR previous_adjustment.expense_id IS DISTINCT FROM p_expense_id
       OR previous_adjustment.reporting_period_id <> p_reporting_period_id THEN
      RAISE EXCEPTION 'A reversal must exactly negate one approved original, retain its currency/rate, and cannot chain.'
        USING ERRCODE = '23514';
    END IF;
  ELSIF p_reversal_of_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only a reversal adjustment may reference reversal_of_id.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.financial_adjustments (
    missionary_id,
    reporting_period_id,
    disbursement_id,
    expense_id,
    adjustment_type,
    amount,
    currency,
    reason,
    status,
    requested_by,
    reversal_of_id,
    adjustment_date,
    exchange_rate_to_ghs,
    exchange_rate_date,
    exchange_rate_source,
    client_submission_id,
    submission_payload
  )
  VALUES (
    target_missionary_id,
    p_reporting_period_id,
    p_disbursement_id,
    p_expense_id,
    p_adjustment_type,
    p_amount::numeric(14,2),
    p_currency,
    btrim(p_reason),
    'pending',
    actor_id,
    p_reversal_of_id,
    p_adjustment_date,
    p_exchange_rate_to_ghs,
    p_exchange_rate_date,
    p_exchange_rate_source,
    p_client_submission_id,
    request_body
  )
  RETURNING * INTO created_adjustment;

  RETURN created_adjustment;
EXCEPTION
  WHEN unique_violation THEN
    SELECT * INTO existing_adjustment
    FROM public.financial_adjustments
    WHERE requested_by = actor_id
      AND client_submission_id = p_client_submission_id;
    IF FOUND AND existing_adjustment.submission_payload = request_body THEN
      RETURN existing_adjustment;
    END IF;
    RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_financial_adjustment(p_adjustment_id uuid)
RETURNS public.financial_adjustments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  adjustment_row public.financial_adjustments%ROWTYPE;
  source_period_id uuid;
  source_available_ghs numeric(14,2);
  carry_forward_total_ghs numeric(14,2);
  next_status text;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.manage') THEN
    RAISE EXCEPTION 'Only an active Financial Director may approve adjustments.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO adjustment_row
  FROM public.financial_adjustments
  WHERE id = p_adjustment_id
  FOR UPDATE;
  IF NOT FOUND OR adjustment_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending adjustments may be approved.'
      USING ERRCODE = '23514';
  END IF;
  IF adjustment_row.requested_by = actor_id THEN
    RAISE EXCEPTION 'An adjustment requester cannot approve their own adjustment.'
      USING ERRCODE = '42501';
  END IF;

  IF adjustment_row.adjustment_type = 'reversal' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.financial_adjustments AS original
      WHERE original.id = adjustment_row.reversal_of_id
        AND original.status = 'approved'
        AND original.reversal_of_id IS NULL
        AND original.amount = -adjustment_row.amount
        AND original.currency = adjustment_row.currency
        AND original.exchange_rate_to_ghs IS NOT DISTINCT FROM adjustment_row.exchange_rate_to_ghs
        AND original.exchange_rate_date IS NOT DISTINCT FROM adjustment_row.exchange_rate_date
        AND original.exchange_rate_source IS NOT DISTINCT FROM adjustment_row.exchange_rate_source
    ) THEN
      RAISE EXCEPTION 'The reversal no longer matches an approved unreversed adjustment.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF adjustment_row.adjustment_type = 'carry_forward' THEN
    SELECT reporting_period_id INTO source_period_id
    FROM public.disbursements
    WHERE id = adjustment_row.disbursement_id;
    PERFORM 1
    FROM public.reporting_periods
    WHERE id = source_period_id
    FOR UPDATE;
    PERFORM private.finance_period_lock(adjustment_row.reporting_period_id);

    source_available_ghs :=
      private.finance_confirmed_received_net_ghs(
        adjustment_row.missionary_id,
        source_period_id
      )
      + private.finance_carry_forward_ghs(
        adjustment_row.missionary_id,
        source_period_id
      )
      - private.finance_approved_expenses_ghs(
        adjustment_row.missionary_id,
        source_period_id
      );

    SELECT coalesce(sum(private.finance_amount_ghs(
      carry.amount, carry.currency, carry.exchange_rate_to_ghs
    )), 0)::numeric(14,2)
    INTO carry_forward_total_ghs
    FROM (
      SELECT prior.amount, prior.currency, prior.exchange_rate_to_ghs
      FROM public.financial_adjustments AS prior
      JOIN public.disbursements AS source_disbursement
        ON source_disbursement.id = prior.disbursement_id
      WHERE prior.missionary_id = adjustment_row.missionary_id
        AND source_disbursement.reporting_period_id = source_period_id
        AND prior.adjustment_type = 'carry_forward'
        AND prior.status = 'approved'
      UNION ALL
      SELECT reversal.amount, reversal.currency, reversal.exchange_rate_to_ghs
      FROM public.financial_adjustments AS reversal
      JOIN public.financial_adjustments AS original
        ON original.id = reversal.reversal_of_id
      JOIN public.disbursements AS source_disbursement
        ON source_disbursement.id = original.disbursement_id
      WHERE reversal.missionary_id = adjustment_row.missionary_id
        AND source_disbursement.reporting_period_id = source_period_id
        AND reversal.adjustment_type = 'reversal'
        AND reversal.status = 'approved'
        AND original.adjustment_type = 'carry_forward'
    ) AS carry;

    IF carry_forward_total_ghs
       + private.finance_amount_ghs(
           adjustment_row.amount,
           adjustment_row.currency,
           adjustment_row.exchange_rate_to_ghs
         )
       > source_available_ghs THEN
      RAISE EXCEPTION 'Approved carry-forward cannot exceed the source period available balance.'
        USING ERRCODE = '23514';
    END IF;
  ELSIF adjustment_row.adjustment_type = 'reversal'
     AND EXISTS (
       SELECT 1
       FROM public.financial_adjustments AS original
       WHERE original.id = adjustment_row.reversal_of_id
         AND original.adjustment_type = 'carry_forward'
     ) THEN
    SELECT source_disbursement.reporting_period_id INTO source_period_id
    FROM public.financial_adjustments AS original
    JOIN public.disbursements AS source_disbursement
      ON source_disbursement.id = original.disbursement_id
    WHERE original.id = adjustment_row.reversal_of_id;
    PERFORM private.finance_period_lock(source_period_id);
    PERFORM private.finance_period_lock(adjustment_row.reporting_period_id);
  ELSE
    PERFORM private.finance_period_lock(adjustment_row.reporting_period_id);
  END IF;

  UPDATE public.financial_adjustments
  SET status = 'approved',
      approved_by = actor_id,
      approved_at = now()
  WHERE id = adjustment_row.id
  RETURNING * INTO adjustment_row;

  IF adjustment_row.disbursement_id IS NOT NULL
     AND adjustment_row.adjustment_type NOT IN ('carry_forward', 'reimbursement')
     AND NOT EXISTS (
       SELECT 1
       FROM public.financial_adjustments AS original
       WHERE original.id = adjustment_row.reversal_of_id
         AND original.adjustment_type IN ('carry_forward', 'reimbursement')
     ) THEN
    next_status := private.finance_refresh_disbursement_status(
      adjustment_row.disbursement_id,
      false
    );
  END IF;

  RETURN adjustment_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_financial_adjustment(
  p_adjustment_id uuid,
  p_reason text
)
RETURNS public.financial_adjustments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  adjustment_row public.financial_adjustments%ROWTYPE;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.manage') THEN
    RAISE EXCEPTION 'Only an active Financial Director may reject adjustments.'
      USING ERRCODE = '42501';
  END IF;
  IF nullif(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A rejection reason is required.' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO adjustment_row
  FROM public.financial_adjustments
  WHERE id = p_adjustment_id
  FOR UPDATE;
  IF NOT FOUND OR adjustment_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending adjustments may be rejected.'
      USING ERRCODE = '23514';
  END IF;
  IF adjustment_row.requested_by = actor_id THEN
    RAISE EXCEPTION 'An adjustment requester cannot reject their own adjustment.'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.financial_adjustments
  SET status = 'rejected',
      rejected_by = actor_id,
      rejected_at = now(),
      rejection_reason = btrim(p_reason)
  WHERE id = adjustment_row.id
  RETURNING * INTO adjustment_row;
  RETURN adjustment_row;
END;
$function$;

CREATE OR REPLACE FUNCTION private.finance_approved_expense_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF OLD.status = 'approved'
     AND (
       NEW.missionary_id IS DISTINCT FROM OLD.missionary_id
       OR NEW.reporting_period_id IS DISTINCT FROM OLD.reporting_period_id
       OR NEW.expense_category_id IS DISTINCT FROM OLD.expense_category_id
       OR NEW.expense_date IS DISTINCT FROM OLD.expense_date
       OR NEW.amount IS DISTINCT FROM OLD.amount
       OR NEW.currency IS DISTINCT FROM OLD.currency
       OR NEW.exchange_rate_to_ghs IS DISTINCT FROM OLD.exchange_rate_to_ghs
       OR NEW.exchange_rate_date IS DISTINCT FROM OLD.exchange_rate_date
       OR NEW.exchange_rate_source IS DISTINCT FROM OLD.exchange_rate_source
       OR NEW.client_submission_id IS DISTINCT FROM OLD.client_submission_id
       OR NEW.submission_payload IS DISTINCT FROM OLD.submission_payload
       OR NEW.description IS DISTINCT FROM OLD.description
     ) THEN
    RAISE EXCEPTION 'Approved expense facts are immutable; use a financial adjustment.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stage3_approved_expense_immutable
  BEFORE UPDATE ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION private.finance_approved_expense_guard();

REVOKE ALL ON FUNCTION private.finance_owns_missionary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.finance_owns_missionary(uuid) TO authenticated;
REVOKE ALL ON FUNCTION private.finance_period_lock(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_audit_row() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_expense_line() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_sync_expense_header() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_prevent_expense_header_override() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_validate_receipt_file(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_expense_receipt() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_disbursement_receipt() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_confirmation_event() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_expense_review() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_resolution() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_adjustment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_expense_write() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_guard_disbursement_write() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_approved_expense_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_transaction_period_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_reporting_period_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_fx_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_validate_period_date(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_validate_fx(character(3), numeric, date, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_amount_ghs(numeric, character(3), numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_confirmed_received_net_ghs(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_approved_expenses_ghs(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_carry_forward_ghs(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_disbursement_effective_native(uuid, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.finance_refresh_disbursement_status(uuid, boolean) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.get_financial_period_balance(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_own_financial_expense(uuid, date, character(3), numeric, date, text, text, jsonb, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_own_financial_expense(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_own_financial_expense(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_financial_expense(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_financial_disbursement(text, uuid, uuid, numeric, character(3), date, text, text, text, numeric, date, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_own_disbursement_confirmation(uuid, text, numeric, date, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resolve_financial_disbursement(uuid, text, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_financial_adjustment(uuid, uuid, uuid, text, numeric, character(3), text, date, numeric, date, text, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_financial_adjustment(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_financial_adjustment(uuid, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_financial_period_balance(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_own_financial_expense(uuid, date, character(3), numeric, date, text, text, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_own_financial_expense(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_own_financial_expense(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_financial_expense(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_financial_disbursement(text, uuid, uuid, numeric, character(3), date, text, text, text, numeric, date, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_own_disbursement_confirmation(uuid, text, numeric, date, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_financial_disbursement(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_financial_adjustment(uuid, uuid, uuid, text, numeric, character(3), text, date, numeric, date, text, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_financial_adjustment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_financial_adjustment(uuid, text) TO authenticated;

COMMIT;
