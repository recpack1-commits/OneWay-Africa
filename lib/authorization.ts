import "server-only";

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type ServerAuthorization = {
  userId: string;
  profile: {
    display_name: string;
    email: string | null;
    status: "active" | "inactive" | "suspended";
  } | null;
  roles: Array<{ code: string; name: string }>;
  permissions: Set<string>;
};

export async function getServerAuthorization(): Promise<ServerAuthorization | null> {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (!user && authError?.name === "AuthSessionMissingError") {
    return null;
  }
  if (authError) {
    throw new Error("Unable to verify your sign-in. Please try again.");
  }
  if (!user) return null;

  const [profileResult, userRolesResult, userPermissionsResult] = await Promise.all([
    supabase
      .from("app_users")
      .select("display_name, email, status")
      .eq("id", user.id)
      .maybeSingle(),
    supabase.from("user_roles").select("role_id, expires_at").eq("user_id", user.id),
    supabase
      .from("user_permissions")
      .select("permission_id, effect, expires_at")
      .eq("user_id", user.id),
  ]);

  if (profileResult.error || userRolesResult.error || userPermissionsResult.error) {
    throw new Error("Unable to load your platform access. Please try again.");
  }

  const activeRoleIds = userRolesResult.data
    .filter((assignment) => !assignment.expires_at || new Date(assignment.expires_at) > new Date())
    .map((assignment) => assignment.role_id);
  const rolePermissionsResult = activeRoleIds.length
    ? await supabase
        .from("role_permissions")
        .select("permission_id")
        .in("role_id", activeRoleIds)
    : { data: [], error: null };
  if (rolePermissionsResult.error) {
    throw new Error("Unable to load your role permissions. Please try again.");
  }

  const activeUserPermissions = userPermissionsResult.data.filter(
    (assignment) => !assignment.expires_at || new Date(assignment.expires_at) > new Date(),
  );
  const permissionIds = Array.from(
    new Set([
      ...rolePermissionsResult.data.map((assignment) => assignment.permission_id),
      ...activeUserPermissions.map((assignment) => assignment.permission_id),
    ]),
  );

  const [rolesResult, permissionsResult] = await Promise.all([
    activeRoleIds.length
      ? supabase.from("roles").select("code, name").in("id", activeRoleIds)
      : Promise.resolve({ data: [], error: null }),
    permissionIds.length
      ? supabase.from("permissions").select("id, code").in("id", permissionIds)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (rolesResult.error || permissionsResult.error) {
    throw new Error("Unable to load your role details. Please try again.");
  }

  const permissionCodesById = new Map(permissionsResult.data.map(({ id, code }) => [id, code]));
  const grantedPermissions = new Set(
    rolePermissionsResult.data
      .map(({ permission_id }) => permissionCodesById.get(permission_id))
      .filter((code): code is string => Boolean(code)),
  );
  for (const assignment of activeUserPermissions) {
    const code = permissionCodesById.get(assignment.permission_id);
    if (!code) continue;
    if (assignment.effect === "deny") grantedPermissions.delete(code);
    else grantedPermissions.add(code);
  }

  return {
    userId: user.id,
    profile: profileResult.data,
    roles: rolesResult.data,
    permissions: grantedPermissions,
  };
}

export async function requirePermission(permission: string) {
  return requireAnyPermission(permission);
}

export async function requireAnyPermission(...permissions: string[]) {
  const authorization = await getServerAuthorization();
  if (!authorization) redirect("/sign-in");

  if (!authorization.profile || authorization.profile.status !== "active") {
    throw new Error("Your account is not active.");
  }
  if (!permissions.some((permission) => authorization.permissions.has(permission))) {
    throw new Error("You do not have permission to perform this action.");
  }

  return authorization;
}
