ALTER TABLE public.app_users
  DROP CONSTRAINT IF EXISTS app_users_status_check;

ALTER TABLE public.app_users
  ADD CONSTRAINT app_users_status_check
  CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text, 'suspended'::text, 'invited'::text]));

UPDATE public.app_users AS app_user
SET status = 'invited'
FROM auth.users AS auth_user
WHERE auth_user.id = app_user.id
  AND auth_user.invited_at IS NOT NULL
  AND auth_user.email_confirmed_at IS NULL
  AND app_user.status IN ('active', 'inactive');

CREATE OR REPLACE FUNCTION private.sync_auth_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  profile_name text;
  profile_status text;
BEGIN
  profile_name := coalesce(
    nullif(trim(NEW.raw_user_meta_data ->> 'display_name'), ''),
    nullif(split_part(NEW.email, '@', 1), ''),
    'New user'
  );
  profile_status := CASE
    WHEN NEW.raw_user_meta_data ->> 'invitation_pending' = 'true' THEN 'invited'
    ELSE 'inactive'
  END;

  INSERT INTO public.app_users (id, display_name, email, status)
  VALUES (NEW.id, profile_name, NEW.email, profile_status)
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email
    WHERE public.app_users.email IS DISTINCT FROM EXCLUDED.email;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.prevent_unaccepted_invitation_activation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.status = 'active'
    AND EXISTS (
      SELECT 1
      FROM auth.users AS auth_user
      WHERE auth_user.id = NEW.id
        AND auth_user.email_confirmed_at IS NULL
        AND (
          auth_user.invited_at IS NOT NULL
          OR auth_user.raw_user_meta_data ->> 'invitation_pending' = 'true'
        )
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = 'check_violation',
      MESSAGE = 'An invitation must be accepted before the account can be activated.';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.prevent_unaccepted_invitation_activation() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS app_users_prevent_unaccepted_invitation_activation ON public.app_users;
CREATE TRIGGER app_users_prevent_unaccepted_invitation_activation
  BEFORE UPDATE OF status ON public.app_users
  FOR EACH ROW
  EXECUTE FUNCTION private.prevent_unaccepted_invitation_activation();

CREATE OR REPLACE FUNCTION private.activate_invited_app_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
    UPDATE public.app_users
    SET status = 'active',
        deactivated_at = NULL,
        deactivated_by = NULL
    WHERE id = NEW.id
      AND status = 'invited';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.activate_invited_app_user() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS activate_invited_app_user ON auth.users;
CREATE TRIGGER activate_invited_app_user
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION private.activate_invited_app_user();

DROP POLICY IF EXISTS app_users_manage_by_permission ON public.app_users;
CREATE POLICY app_users_manage_by_permission ON public.app_users
  FOR UPDATE TO authenticated
  USING ((SELECT private.has_permission('users.manage')))
  WITH CHECK (
    (SELECT private.has_permission('users.manage'))
    AND (id <> (SELECT auth.uid()) OR status = 'active')
  );

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
  ELSIF TG_TABLE_NAME = 'roles' THEN
    IF TG_OP = 'INSERT' THEN
      entity_id := NEW.id;
      after_values := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
      entity_id := OLD.id;
      before_values := to_jsonb(OLD);
    ELSE
      entity_id := NEW.id;
      before_values := to_jsonb(OLD);
      after_values := to_jsonb(NEW);
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

REVOKE ALL ON FUNCTION private.audit_user_access_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS roles_audit_access_change ON public.roles;
CREATE TRIGGER roles_audit_access_change
  AFTER INSERT OR UPDATE OR DELETE ON public.roles
  FOR EACH ROW
  EXECUTE FUNCTION private.audit_user_access_change('roles');
