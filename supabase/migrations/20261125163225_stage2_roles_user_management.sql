ALTER TABLE public.app_users
  ADD COLUMN IF NOT EXISTS email text;

CREATE INDEX IF NOT EXISTS app_users_email_idx
  ON public.app_users (lower(email))
  WHERE email IS NOT NULL;

INSERT INTO public.app_users (id, display_name, email, status)
SELECT
  u.id,
  coalesce(nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''), nullif(split_part(u.email, '@', 1), ''), 'New user'),
  u.email,
  'inactive'
FROM auth.users AS u
ON CONFLICT (id) DO NOTHING;

UPDATE public.app_users AS app_user
SET email = auth_user.email
FROM auth.users AS auth_user
WHERE app_user.id = auth_user.id
  AND app_user.email IS NULL
  AND auth_user.email IS NOT NULL;

INSERT INTO public.roles (code, name, description)
VALUES
  ('system_administrator', 'System Administrator', 'Manages platform users and configuration; does not receive confidential financial access by default.'),
  ('office_staff', 'Office Staff', 'Supports office operations, field reporting, and inventory.'),
  ('missionary', 'Missionary', 'Submits and views assigned field reports and personal records.'),
  ('field_director', 'Field Director', 'Oversees missionary and field reporting operations.'),
  ('financial_director', 'Financial Director', 'Manages confidential financial operations.')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.permissions (code, module, description, is_sensitive)
VALUES
  ('users.read', 'users', 'View the user directory.', false),
  ('users.manage', 'users', 'Invite users, assign roles, and activate or deactivate accounts.', false),
  ('missionaries.read_all', 'missionaries', 'View missionary records across the platform.', false),
  ('missionaries.manage', 'missionaries', 'Manage missionary records.', false),
  ('field.reports.read', 'field', 'View field reports.', false),
  ('field.reports.manage', 'field', 'Create and manage field reports.', false),
  ('inventory.read', 'inventory', 'View inventory records.', false),
  ('inventory.manage', 'inventory', 'Manage inventory records.', false),
  ('financial.read', 'finance', 'View confidential financial records.', true),
  ('financial.manage', 'finance', 'Manage confidential financial records.', true),
  ('financial.roles.manage', 'finance', 'Assign roles that grant confidential financial access.', true)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (
  VALUES
    ('system_administrator', 'users.read'),
    ('system_administrator', 'users.manage'),
    ('system_administrator', 'missionaries.read_all'),
    ('system_administrator', 'missionaries.manage'),
    ('system_administrator', 'field.reports.read'),
    ('system_administrator', 'field.reports.manage'),
    ('system_administrator', 'inventory.read'),
    ('system_administrator', 'inventory.manage'),
    ('office_staff', 'users.read'),
    ('office_staff', 'missionaries.read_all'),
    ('office_staff', 'field.reports.read'),
    ('office_staff', 'field.reports.manage'),
    ('office_staff', 'inventory.read'),
    ('office_staff', 'inventory.manage'),
    ('missionary', 'field.reports.read'),
    ('missionary', 'field.reports.manage'),
    ('field_director', 'missionaries.read_all'),
    ('field_director', 'missionaries.manage'),
    ('field_director', 'field.reports.read'),
    ('field_director', 'field.reports.manage'),
    ('financial_director', 'financial.read'),
    ('financial_director', 'financial.manage'),
    ('financial_director', 'financial.roles.manage'),
    ('financial_director', 'users.read')
) AS assignment(role_code, permission_code)
JOIN public.roles AS r ON r.code = assignment.role_code
JOIN public.permissions AS p ON p.code = assignment.permission_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

UPDATE public.permissions
SET is_sensitive = true
WHERE code IN ('financial.read', 'financial.manage', 'financial.roles.manage')
  AND is_sensitive IS DISTINCT FROM true;

DELETE FROM public.role_permissions AS rp
USING public.roles AS r, public.permissions AS p
WHERE rp.role_id = r.id
  AND rp.permission_id = p.id
  AND r.code = 'system_administrator'
  AND p.is_sensitive;

CREATE OR REPLACE FUNCTION private.has_permission(p_permission_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_users AS u
    WHERE u.id = (SELECT auth.uid())
      AND u.status = 'active'
      AND (
        EXISTS (
          SELECT 1
          FROM public.user_roles AS ur
          JOIN public.role_permissions AS rp ON rp.role_id = ur.role_id
          JOIN public.permissions AS p ON p.id = rp.permission_id
          WHERE ur.user_id = u.id
            AND (ur.expires_at IS NULL OR ur.expires_at > now())
            AND p.code = p_permission_code
        )
        OR EXISTS (
          SELECT 1
          FROM public.user_permissions AS up
          JOIN public.permissions AS p ON p.id = up.permission_id
          WHERE up.user_id = u.id
            AND up.effect = 'allow'
            AND (up.expires_at IS NULL OR up.expires_at > now())
            AND p.code = p_permission_code
        )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_permissions AS up
        JOIN public.permissions AS p ON p.id = up.permission_id
        WHERE up.user_id = u.id
          AND up.effect = 'deny'
          AND (up.expires_at IS NULL OR up.expires_at > now())
          AND p.code = p_permission_code
      )
  );
$function$;

CREATE OR REPLACE FUNCTION private.is_active_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_users AS u
    WHERE u.id = (SELECT auth.uid())
      AND u.status = 'active'
  );
$function$;

CREATE OR REPLACE FUNCTION private.sync_auth_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  profile_name text;
BEGIN
  profile_name := coalesce(
    nullif(trim(NEW.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(NEW.email, '@', 1), ''),
    'New user'
  );

  INSERT INTO public.app_users (id, display_name, email, status)
  VALUES (NEW.id, profile_name, NEW.email, 'inactive')
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email
    WHERE public.app_users.email IS DISTINCT FROM EXCLUDED.email;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS sync_auth_user_profile ON auth.users;
CREATE TRIGGER sync_auth_user_profile
  AFTER INSERT OR UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION private.sync_auth_user_profile();

CREATE OR REPLACE FUNCTION private.audit_user_access_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  entity_id uuid;
  before_values jsonb;
  after_values jsonb;
  action_name text;
  entity_name text;
BEGIN
  entity_name := TG_ARGV[0];
  action_name := lower(TG_OP);

  IF TG_TABLE_NAME = 'app_users' THEN
    IF TG_OP = 'INSERT' THEN
      entity_id := NEW.id;
      after_values := jsonb_build_object(
        'display_name', NEW.display_name,
        'status', NEW.status,
        'deactivated_at', NEW.deactivated_at,
        'deactivated_by', NEW.deactivated_by
      );
    ELSIF TG_OP = 'DELETE' THEN
      entity_id := OLD.id;
      before_values := jsonb_build_object(
        'display_name', OLD.display_name,
        'status', OLD.status,
        'deactivated_at', OLD.deactivated_at,
        'deactivated_by', OLD.deactivated_by
      );
    ELSE
      entity_id := NEW.id;
      before_values := jsonb_build_object(
        'display_name', OLD.display_name,
        'status', OLD.status,
        'deactivated_at', OLD.deactivated_at,
        'deactivated_by', OLD.deactivated_by
      );
      after_values := jsonb_build_object(
        'display_name', NEW.display_name,
        'status', NEW.status,
        'deactivated_at', NEW.deactivated_at,
        'deactivated_by', NEW.deactivated_by
      );
    END IF;
  ELSIF TG_TABLE_NAME = 'role_permissions' THEN
    IF TG_OP = 'INSERT' THEN
      entity_id := NEW.role_id;
      after_values := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
      entity_id := OLD.role_id;
      before_values := to_jsonb(OLD);
    ELSE
      entity_id := NEW.role_id;
      before_values := to_jsonb(OLD);
      after_values := to_jsonb(NEW);
    END IF;
  ELSE
    IF TG_OP = 'INSERT' THEN
      entity_id := NEW.user_id;
      after_values := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
      entity_id := OLD.user_id;
      before_values := to_jsonb(OLD);
    ELSE
      entity_id := NEW.user_id;
      before_values := to_jsonb(OLD);
      after_values := to_jsonb(NEW);
    END IF;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, before_values, after_values)
  VALUES ((SELECT auth.uid()), action_name, entity_name, entity_id, before_values, after_values);

  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION private.prevent_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Audit logs are append-only.';
END;
$function$;

DROP TRIGGER IF EXISTS app_users_audit_access_change ON public.app_users;
CREATE TRIGGER app_users_audit_access_change
  AFTER INSERT OR UPDATE OF display_name, status, deactivated_at, deactivated_by ON public.app_users
  FOR EACH ROW
  EXECUTE FUNCTION private.audit_user_access_change('app_users');

DROP TRIGGER IF EXISTS user_roles_audit_access_change ON public.user_roles;
CREATE TRIGGER user_roles_audit_access_change
  AFTER INSERT OR UPDATE OR DELETE ON public.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION private.audit_user_access_change('user_roles');

DROP TRIGGER IF EXISTS user_permissions_audit_access_change ON public.user_permissions;
CREATE TRIGGER user_permissions_audit_access_change
  AFTER INSERT OR UPDATE OR DELETE ON public.user_permissions
  FOR EACH ROW
  EXECUTE FUNCTION private.audit_user_access_change('user_permissions');

DROP TRIGGER IF EXISTS role_permissions_audit_access_change ON public.role_permissions;
CREATE TRIGGER role_permissions_audit_access_change
  AFTER INSERT OR UPDATE OR DELETE ON public.role_permissions
  FOR EACH ROW
  EXECUTE FUNCTION private.audit_user_access_change('role_permissions');

DROP TRIGGER IF EXISTS audit_logs_append_only ON public.audit_logs;
CREATE TRIGGER audit_logs_append_only
  BEFORE UPDATE OR DELETE ON public.audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION private.prevent_audit_log_mutation();

DROP TRIGGER IF EXISTS audit_logs_no_truncate ON public.audit_logs;
CREATE TRIGGER audit_logs_no_truncate
  BEFORE TRUNCATE ON public.audit_logs
  FOR EACH STATEMENT
  EXECUTE FUNCTION private.prevent_audit_log_mutation();

DROP POLICY IF EXISTS app_users_manage_by_permission ON public.app_users;
CREATE POLICY app_users_manage_by_permission ON public.app_users
  FOR UPDATE TO authenticated
  USING ((SELECT private.has_permission('users.manage')))
  WITH CHECK ((SELECT private.has_permission('users.manage')));

DROP POLICY IF EXISTS app_users_read_self_or_admin ON public.app_users;
CREATE POLICY app_users_read_self_or_authorized ON public.app_users
  FOR SELECT TO authenticated
  USING (
    id = (SELECT auth.uid())
    OR (SELECT private.has_permission('users.read'))
    OR (SELECT private.has_permission('users.manage'))
  );

DROP POLICY IF EXISTS audit_logs_read_by_permission ON public.audit_logs;
CREATE POLICY audit_logs_read_by_permission ON public.audit_logs
  FOR SELECT TO authenticated
  USING ((SELECT private.has_permission('users.manage')));

DROP POLICY IF EXISTS user_roles_read_self_or_admin ON public.user_roles;
CREATE POLICY user_roles_read_self_or_authorized ON public.user_roles
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR (SELECT private.has_permission('users.read'))
    OR (SELECT private.has_permission('users.manage'))
  );

DROP POLICY IF EXISTS user_roles_manage_by_permission ON public.user_roles;
CREATE POLICY user_roles_manage_by_permission ON public.user_roles
  FOR INSERT TO authenticated
  WITH CHECK (
    (
      (SELECT private.has_permission('users.manage'))
      AND NOT EXISTS (
        SELECT 1
        FROM public.role_permissions AS rp
        JOIN public.permissions AS p ON p.id = rp.permission_id
        WHERE rp.role_id = user_roles.role_id AND p.is_sensitive
      )
    )
    OR (
      (SELECT private.has_permission('financial.roles.manage'))
      AND EXISTS (
        SELECT 1
        FROM public.role_permissions AS rp
        JOIN public.permissions AS p ON p.id = rp.permission_id
        WHERE rp.role_id = user_roles.role_id AND p.is_sensitive
      )
    )
  );
CREATE POLICY user_roles_delete_by_permission ON public.user_roles
  FOR DELETE TO authenticated
  USING (
    (
      (SELECT private.has_permission('users.manage'))
      AND NOT EXISTS (
        SELECT 1
        FROM public.role_permissions AS rp
        JOIN public.permissions AS p ON p.id = rp.permission_id
        WHERE rp.role_id = user_roles.role_id AND p.is_sensitive
      )
    )
    OR (
      (SELECT private.has_permission('financial.roles.manage'))
      AND EXISTS (
        SELECT 1
        FROM public.role_permissions AS rp
        JOIN public.permissions AS p ON p.id = rp.permission_id
        WHERE rp.role_id = user_roles.role_id AND p.is_sensitive
      )
    )
  );

DROP POLICY IF EXISTS user_permissions_read_self_or_admin ON public.user_permissions;
CREATE POLICY user_permissions_read_self_or_authorized ON public.user_permissions
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR (SELECT private.has_permission('users.read'))
    OR (SELECT private.has_permission('users.manage'))
  );

DROP POLICY IF EXISTS user_permissions_manage_by_permission ON public.user_permissions;
CREATE POLICY user_permissions_manage_by_permission ON public.user_permissions
  FOR INSERT TO authenticated
  WITH CHECK (
    (
      (SELECT private.has_permission('users.manage'))
      AND NOT EXISTS (
        SELECT 1 FROM public.permissions AS p
        WHERE p.id = user_permissions.permission_id AND p.is_sensitive
      )
    )
    OR (
      (SELECT private.has_permission('financial.roles.manage'))
      AND EXISTS (
        SELECT 1 FROM public.permissions AS p
        WHERE p.id = user_permissions.permission_id AND p.is_sensitive
      )
    )
  );
CREATE POLICY user_permissions_update_by_permission ON public.user_permissions
  FOR UPDATE TO authenticated
  USING (
    (
      (SELECT private.has_permission('users.manage'))
      AND NOT EXISTS (
        SELECT 1 FROM public.permissions AS p
        WHERE p.id = user_permissions.permission_id AND p.is_sensitive
      )
    )
    OR (
      (SELECT private.has_permission('financial.roles.manage'))
      AND EXISTS (
        SELECT 1 FROM public.permissions AS p
        WHERE p.id = user_permissions.permission_id AND p.is_sensitive
      )
    )
  )
  WITH CHECK (
    (
      (SELECT private.has_permission('users.manage'))
      AND NOT EXISTS (
        SELECT 1 FROM public.permissions AS p
        WHERE p.id = user_permissions.permission_id AND p.is_sensitive
      )
    )
    OR (
      (SELECT private.has_permission('financial.roles.manage'))
      AND EXISTS (
        SELECT 1 FROM public.permissions AS p
        WHERE p.id = user_permissions.permission_id AND p.is_sensitive
      )
    )
  );
CREATE POLICY user_permissions_delete_by_permission ON public.user_permissions
  FOR DELETE TO authenticated
  USING (
    (
      (SELECT private.has_permission('users.manage'))
      AND NOT EXISTS (
        SELECT 1 FROM public.permissions AS p
        WHERE p.id = user_permissions.permission_id AND p.is_sensitive
      )
    )
    OR (
      (SELECT private.has_permission('financial.roles.manage'))
      AND EXISTS (
        SELECT 1 FROM public.permissions AS p
        WHERE p.id = user_permissions.permission_id AND p.is_sensitive
      )
    )
  );

DROP POLICY IF EXISTS expenses_financial_or_own_read ON public.expenses;
CREATE POLICY expenses_financial_or_own_read ON public.expenses
  FOR SELECT TO authenticated
  USING (
    (SELECT private.has_permission('financial.read'))
    OR (
      (SELECT private.is_active_user())
      AND EXISTS (
        SELECT 1 FROM public.missionaries AS m
        WHERE m.id = expenses.missionary_id AND m.app_user_id = (SELECT auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS disbursements_financial_or_own_read ON public.disbursements;
CREATE POLICY disbursements_financial_or_own_read ON public.disbursements
  FOR SELECT TO authenticated
  USING (
    (SELECT private.has_permission('financial.read'))
    OR (
      (SELECT private.is_active_user())
      AND EXISTS (
        SELECT 1 FROM public.missionaries AS m
        WHERE m.id = disbursements.missionary_id AND m.app_user_id = (SELECT auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS financial_adjustments_financial_read ON public.financial_adjustments;
CREATE POLICY financial_adjustments_financial_read ON public.financial_adjustments
  FOR SELECT TO authenticated
  USING ((SELECT private.has_permission('financial.read')));

DROP POLICY IF EXISTS disbursement_confirmations_financial_or_own_read ON public.disbursement_confirmations;
CREATE POLICY disbursement_confirmations_financial_or_own_read ON public.disbursement_confirmations
  FOR SELECT TO authenticated
  USING (
    (SELECT private.has_permission('financial.read'))
    OR confirmed_by = (SELECT auth.uid())
  );

DROP POLICY IF EXISTS disbursement_receipts_financial_or_own_read ON public.disbursement_receipts;
CREATE POLICY disbursement_receipts_financial_or_own_read ON public.disbursement_receipts
  FOR SELECT TO authenticated
  USING (
    (SELECT private.has_permission('financial.read'))
    OR uploaded_by = (SELECT auth.uid())
  );

DROP POLICY IF EXISTS expense_receipts_financial_or_own_read ON public.expense_receipts;
CREATE POLICY expense_receipts_financial_or_own_read ON public.expense_receipts
  FOR SELECT TO authenticated
  USING (
    (SELECT private.has_permission('financial.read'))
    OR uploaded_by = (SELECT auth.uid())
  );

DROP POLICY IF EXISTS expense_reviews_financial_read ON public.expense_reviews;
CREATE POLICY expense_reviews_financial_read ON public.expense_reviews
  FOR SELECT TO authenticated
  USING ((SELECT private.has_permission('financial.read')));

REVOKE ALL ON FUNCTION private.sync_auth_user_profile() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.audit_user_access_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.prevent_audit_log_mutation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.has_permission(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.has_permission(text) TO authenticated;
REVOKE ALL ON FUNCTION private.is_active_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.is_active_user() TO authenticated;

GRANT UPDATE (status, deactivated_at, deactivated_by) ON public.app_users TO authenticated;
GRANT INSERT, DELETE ON public.user_roles TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.user_permissions TO authenticated;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.audit_logs FROM anon, authenticated;
