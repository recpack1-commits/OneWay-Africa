BEGIN;

CREATE TABLE public.financial_expense_update_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  expense_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  client_submission_id uuid NOT NULL,
  request_payload jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT financial_expense_update_requests_pkey PRIMARY KEY (id),
  CONSTRAINT financial_expense_update_requests_expense_fkey
    FOREIGN KEY (expense_id) REFERENCES public.expenses(id) ON DELETE RESTRICT,
  CONSTRAINT financial_expense_update_requests_actor_fkey
    FOREIGN KEY (actor_user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_expense_update_requests_key
    UNIQUE (actor_user_id, client_submission_id)
);

ALTER TABLE public.financial_expense_update_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.financial_expense_update_requests FROM PUBLIC, anon, authenticated;

CREATE TABLE public.financial_receipt_upload_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  actor_user_id uuid NOT NULL,
  record_type text NOT NULL,
  record_id uuid NOT NULL,
  client_submission_id uuid NOT NULL,
  file_asset_id uuid NOT NULL,
  supersedes_receipt_id uuid,
  request_payload jsonb NOT NULL,
  receipt_link_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT financial_receipt_upload_requests_pkey PRIMARY KEY (id),
  CONSTRAINT financial_receipt_upload_requests_actor_fkey
    FOREIGN KEY (actor_user_id) REFERENCES public.app_users(id) ON DELETE RESTRICT,
  CONSTRAINT financial_receipt_upload_requests_file_asset_fkey
    FOREIGN KEY (file_asset_id) REFERENCES public.file_assets(id) ON DELETE RESTRICT,
  CONSTRAINT financial_receipt_upload_requests_type_check
    CHECK (record_type IN ('expense', 'disbursement')),
  CONSTRAINT financial_receipt_upload_requests_key
    UNIQUE (actor_user_id, record_type, client_submission_id)
);
ALTER TABLE public.financial_receipt_upload_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.financial_receipt_upload_requests FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_own_financial_expense(
  p_expense_id uuid,
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
  expense_row public.expenses%ROWTYPE;
  line_row record;
  existing_payload jsonb;
  canonical_lines jsonb;
  canonical_payload jsonb;
  total_amount numeric(14,2);
  line_count bigint;
  category_count bigint;
BEGIN
  IF actor_id IS NULL
     OR NOT private.is_active_user()
     OR NOT private.has_permission('financial.expenses.own_manage') THEN
    RAISE EXCEPTION 'Not authorized to edit this expense.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO expense_row
  FROM public.expenses
  WHERE id = p_expense_id
  FOR UPDATE;
  IF NOT FOUND
     OR NOT private.finance_owns_missionary(expense_row.missionary_id) THEN
    RAISE EXCEPTION 'Expense not found or not owned by the active missionary.'
      USING ERRCODE = '42501';
  END IF;

  IF p_client_submission_id IS NULL
     OR p_lines IS NULL
     OR jsonb_typeof(p_lines) <> 'array'
     OR jsonb_array_length(p_lines) = 0
     OR jsonb_array_length(p_lines) > 100
     OR nullif(btrim(p_description), '') IS NULL THEN
    RAISE EXCEPTION 'An edit key, description, and one to one hundred item lines are required.'
      USING ERRCODE = '23514';
  END IF;

  PERFORM private.finance_period_lock(expense_row.reporting_period_id);
  IF p_reporting_period_id <> expense_row.reporting_period_id THEN
    PERFORM private.finance_period_lock(p_reporting_period_id);
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
     OR total_amount <= 0
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
     ) THEN
    RAISE EXCEPTION 'Expense lines contain invalid or unapproved data.'
      USING ERRCODE = '23514';
  END IF;

  canonical_payload := jsonb_build_object(
    'expense_id', p_expense_id,
    'reporting_period_id', p_reporting_period_id,
    'expense_date', p_expense_date,
    'currency', p_currency,
    'exchange_rate_to_ghs', p_exchange_rate_to_ghs,
    'exchange_rate_date', p_exchange_rate_date,
    'exchange_rate_source', p_exchange_rate_source,
    'description', btrim(p_description),
    'lines', canonical_lines
  );

  SELECT request_payload
  INTO existing_payload
  FROM public.financial_expense_update_requests
  WHERE actor_user_id = actor_id
    AND client_submission_id = p_client_submission_id;
  IF FOUND THEN
    IF existing_payload IS DISTINCT FROM canonical_payload THEN
      RAISE EXCEPTION 'The expense edit idempotency key was reused with a different payload.'
        USING ERRCODE = '23505';
    END IF;
    RETURN p_expense_id;
  END IF;

  IF expense_row.status NOT IN ('draft', 'queried') THEN
    RAISE EXCEPTION 'Only your draft or queried expense can be edited.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.financial_expense_update_requests (
    expense_id, actor_user_id, client_submission_id, request_payload
  )
  VALUES (p_expense_id, actor_id, p_client_submission_id, canonical_payload);

  FOR line_row IN
    SELECT *
    FROM jsonb_to_recordset(p_lines) AS line(
      line_number integer,
      expense_category_id uuid,
      description text,
      amount numeric
    )
    ORDER BY line.line_number
  LOOP
    UPDATE public.expense_lines
    SET expense_category_id = line_row.expense_category_id,
        description = btrim(line_row.description),
        amount = line_row.amount::numeric(14,2)
    WHERE expense_id = p_expense_id
      AND line_number = line_row.line_number;

    IF NOT FOUND THEN
      INSERT INTO public.expense_lines (
        expense_id, expense_category_id, line_number, description, amount
      )
      VALUES (
        p_expense_id,
        line_row.expense_category_id,
        line_row.line_number,
        btrim(line_row.description),
        line_row.amount::numeric(14,2)
      );
    END IF;
  END LOOP;

  DELETE FROM public.expense_lines AS saved_line
  WHERE saved_line.expense_id = p_expense_id
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_to_recordset(p_lines) AS line(
        line_number integer,
        expense_category_id uuid,
        description text,
        amount numeric
      )
      WHERE line.line_number = saved_line.line_number
    );

  UPDATE public.expenses
  SET reporting_period_id = p_reporting_period_id,
      expense_date = p_expense_date,
      currency = p_currency,
      exchange_rate_to_ghs = p_exchange_rate_to_ghs,
      exchange_rate_date = p_exchange_rate_date,
      exchange_rate_source = p_exchange_rate_source,
      description = btrim(p_description),
      updated_at = now()
  WHERE id = p_expense_id;

  RETURN p_expense_id;
EXCEPTION
  WHEN unique_violation THEN
    SELECT request_payload
    INTO existing_payload
    FROM public.financial_expense_update_requests
    WHERE actor_user_id = actor_id
      AND client_submission_id = p_client_submission_id;
    IF FOUND AND existing_payload = canonical_payload THEN
      RETURN p_expense_id;
    END IF;
    IF FOUND THEN
      RAISE EXCEPTION 'The expense edit idempotency key conflicts with a different payload.'
        USING ERRCODE = '23505';
    END IF;
    RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.link_financial_receipt(
  p_record_type text,
  p_record_id uuid,
  p_file_asset_id uuid,
  p_supersedes_receipt_id uuid,
  p_client_submission_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  actor_id uuid := (SELECT auth.uid());
  request_body jsonb;
  existing_request public.financial_receipt_upload_requests%ROWTYPE;
  receipt_link_id uuid;
  created_link_id uuid;
  expense_row public.expenses%ROWTYPE;
  disbursement_row public.disbursements%ROWTYPE;
BEGIN
  IF actor_id IS NULL OR NOT private.is_active_user() THEN
    RAISE EXCEPTION 'An active authenticated user is required.'
      USING ERRCODE = '42501';
  END IF;
  IF p_record_type NOT IN ('expense', 'disbursement')
     OR p_record_id IS NULL
     OR p_file_asset_id IS NULL
     OR p_client_submission_id IS NULL THEN
    RAISE EXCEPTION 'A valid finance record, uploaded file, and retry key are required.'
      USING ERRCODE = '23514';
  END IF;
  request_body := jsonb_build_object(
    'record_type', p_record_type,
    'record_id', p_record_id,
    'file_asset_id', p_file_asset_id,
    'supersedes_receipt_id', p_supersedes_receipt_id
  );
  IF p_record_type = 'expense' THEN
    IF NOT private.has_permission('financial.expenses.own_manage') THEN
      RAISE EXCEPTION 'Not authorized to attach an expense receipt.'
        USING ERRCODE = '42501';
    END IF;
    SELECT * INTO expense_row
    FROM public.expenses
    WHERE id = p_record_id
    FOR UPDATE;
    IF NOT FOUND
       OR NOT private.finance_owns_missionary(expense_row.missionary_id) THEN
      RAISE EXCEPTION 'Expense not found or not owned by the active missionary.'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF NOT private.has_permission('financial.disbursements.evidence') THEN
      RAISE EXCEPTION 'Not authorized to attach payment evidence.'
        USING ERRCODE = '42501';
    END IF;
    SELECT * INTO disbursement_row
    FROM public.disbursements
    WHERE id = p_record_id
    FOR UPDATE;
    IF NOT FOUND OR disbursement_row.created_by <> actor_id THEN
      RAISE EXCEPTION 'Payment evidence may only be attached to a disbursement you created.'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  PERFORM private.finance_validate_receipt_file(p_file_asset_id);
  IF NOT EXISTS (
    SELECT 1 FROM public.file_assets
    WHERE id = p_file_asset_id AND uploaded_by = actor_id
  ) THEN
    RAISE EXCEPTION 'The receipt file must belong to the authenticated uploader.'
      USING ERRCODE = '42501';
  END IF;
  SELECT * INTO existing_request
  FROM public.financial_receipt_upload_requests
  WHERE actor_user_id = actor_id
    AND record_type = p_record_type
    AND client_submission_id = p_client_submission_id;
  IF FOUND THEN
    IF existing_request.request_payload IS DISTINCT FROM request_body THEN
      RAISE EXCEPTION 'The receipt upload idempotency key was reused with a different payload.'
        USING ERRCODE = '23505';
    END IF;
    RETURN existing_request.receipt_link_id;
  END IF;
  IF p_record_type = 'expense' AND expense_row.status NOT IN ('draft', 'queried') THEN
    RAISE EXCEPTION 'Receipts can only be attached to your draft or queried expense.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.financial_receipt_upload_requests (
    actor_user_id, record_type, record_id, client_submission_id,
    file_asset_id, supersedes_receipt_id, request_payload
  )
  VALUES (
    actor_id, p_record_type, p_record_id, p_client_submission_id,
    p_file_asset_id, p_supersedes_receipt_id, request_body
  );

  IF p_record_type = 'expense' THEN
    INSERT INTO public.expense_receipts (
      expense_id, file_asset_id, uploaded_by, supersedes_receipt_id
    )
    VALUES (p_record_id, p_file_asset_id, actor_id, p_supersedes_receipt_id)
    RETURNING id INTO receipt_link_id;
  ELSE
    IF p_supersedes_receipt_id IS NOT NULL THEN
      RAISE EXCEPTION 'Payment evidence cannot replace an expense receipt.'
        USING ERRCODE = '23514';
    END IF;
    INSERT INTO public.disbursement_receipts (
      disbursement_id, file_asset_id, uploaded_by
    )
    VALUES (p_record_id, p_file_asset_id, actor_id)
    RETURNING id INTO receipt_link_id;
  END IF;

  created_link_id := receipt_link_id;
  UPDATE public.financial_receipt_upload_requests
  SET receipt_link_id = created_link_id
  WHERE actor_user_id = actor_id
    AND record_type = p_record_type
    AND client_submission_id = p_client_submission_id;
  RETURN receipt_link_id;
EXCEPTION
  WHEN unique_violation THEN
    SELECT * INTO existing_request
    FROM public.financial_receipt_upload_requests
    WHERE actor_user_id = actor_id
      AND record_type = p_record_type
      AND client_submission_id = p_client_submission_id;
    IF FOUND AND existing_request.request_payload = request_body THEN
      RETURN existing_request.receipt_link_id;
    END IF;
    IF FOUND THEN
      RAISE EXCEPTION 'The receipt upload idempotency key conflicts with a different payload.'
        USING ERRCODE = '23505';
    END IF;
    RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_financial_missionary_recipients()
RETURNS TABLE (id uuid, display_name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT private.is_active_user()
     OR NOT (
       private.has_permission('financial.read')
       OR private.has_permission('financial.disbursements.create')
     ) THEN
    RAISE EXCEPTION 'Not authorized to list financial recipients.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT missionary.id, missionary.display_name
  FROM public.missionaries AS missionary
  WHERE missionary.status = 'active'
  ORDER BY missionary.display_name, missionary.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_own_financial_expense(uuid, uuid, date, character(3), numeric, date, text, text, jsonb, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_own_financial_expense(uuid, uuid, date, character(3), numeric, date, text, text, jsonb, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.list_financial_missionary_recipients() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_financial_missionary_recipients() TO authenticated;
REVOKE ALL ON FUNCTION public.link_financial_receipt(text, uuid, uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_financial_receipt(text, uuid, uuid, uuid, uuid) TO authenticated;

COMMIT;
