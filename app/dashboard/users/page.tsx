import { UserManagementControls, InviteUserForm } from "@/components/dashboard/user-management-controls";
import { getServerAuthorization } from "@/lib/authorization";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function UsersPage() {
  const authorization = await getServerAuthorization();

  if (!authorization?.profile || authorization.profile.status !== "active") {
    return null;
  }
  if (!authorization.permissions.has("users.read")) {
    return (
      <section className="rounded-3xl border border-white bg-white p-7 shadow-card sm:p-10">
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-leaf">Access denied</p>
        <h1 className="mt-3 text-2xl font-semibold tracking-tight text-ink">User directory</h1>
        <p className="mt-3 text-sm leading-6 text-ink/70">
          Your account does not have permission to view user records.
        </p>
      </section>
    );
  }

  const supabase = await createSupabaseServerClient();
  const { data: users, error: usersError } = await supabase
    .from("app_users")
    .select("id, display_name, email, status, created_at")
    .order("display_name");
  if (usersError) throw new Error("Unable to load the user directory. Please try again.");

  const { data: roles, error: rolesError } = await supabase
    .from("roles")
    .select("id, code, name")
    .order("name");
  if (rolesError) throw new Error("Unable to load available roles. Please try again.");

  const userIds = users.map(({ id }) => id);
  const roleIds = roles.map(({ id }) => id);
  const [userRolesResult, rolePermissionsResult] = await Promise.all([
    userIds.length
      ? supabase
          .from("user_roles")
          .select("user_id, role_id, expires_at")
          .in("user_id", userIds)
      : Promise.resolve({ data: [], error: null }),
    roleIds.length
      ? supabase.from("role_permissions").select("role_id, permission_id").in("role_id", roleIds)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (userRolesResult.error || rolePermissionsResult.error) {
    throw new Error("Unable to load user role assignments. Please try again.");
  }

  const permissionIds = Array.from(
    new Set(rolePermissionsResult.data.map(({ permission_id }) => permission_id)),
  );
  const { data: permissions, error: permissionsError } = permissionIds.length
    ? await supabase.from("permissions").select("id, is_sensitive").in("id", permissionIds)
    : { data: [], error: null };
  if (permissionsError) throw new Error("Unable to verify role access. Please try again.");

  const sensitivePermissionIds = new Set(
    permissions.filter(({ is_sensitive }) => is_sensitive).map(({ id }) => id),
  );
  const rolesWithSensitiveAccess = new Set(
    rolePermissionsResult.data
      .filter(({ permission_id }) => sensitivePermissionIds.has(permission_id))
      .map(({ role_id }) => role_id),
  );
  const canManageUsers = authorization.permissions.has("users.manage");
  const canManageSensitive = authorization.permissions.has("financial.roles.manage");
  const availableRoles = roles.filter(
    (role) =>
      rolesWithSensitiveAccess.has(role.id)
        ? canManageSensitive
        : canManageUsers,
  );
  const rolesById = new Map(roles.map((role) => [role.id, role]));
  const assignmentsByUser = new Map<string, Array<{ id: string; code: string; name: string }>>();

  for (const assignment of userRolesResult.data) {
    if (assignment.expires_at && new Date(assignment.expires_at) <= new Date()) continue;
    const role = rolesById.get(assignment.role_id);
    if (!role) continue;
    const currentAssignments = assignmentsByUser.get(assignment.user_id) ?? [];
    currentAssignments.push({ id: role.id, code: role.code, name: role.name });
    assignmentsByUser.set(assignment.user_id, currentAssignments);
  }

  return (
    <div className="space-y-8">
      <header>
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-leaf">Access management</p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-ink">User directory</h1>
        <p className="mt-3 max-w-2xl text-sm leading-6 text-ink/70">
          Manage platform access for 2027 operations. Invited users remain blocked until they accept
          their invitation.
        </p>
      </header>

      {(canManageUsers || canManageSensitive) && availableRoles.length > 0 && (
        <section aria-labelledby="invite-heading" className="space-y-4">
          <div>
            <h2 className="text-lg font-semibold text-ink" id="invite-heading">
              Invite a user
            </h2>
            <p className="mt-1 text-sm text-ink/65">
              The invitee receives a secure account setup link. System Administrators can assign
              standard roles; only Financial Directors can assign roles with confidential
              financial access.
            </p>
          </div>
          <InviteUserForm roles={availableRoles} />
        </section>
      )}

      <section aria-labelledby="directory-heading">
        <div className="mb-4 flex items-baseline justify-between gap-4">
          <h2 className="text-lg font-semibold text-ink" id="directory-heading">
            Platform accounts
          </h2>
          <span className="text-sm text-ink/60">{users.length} accounts</span>
        </div>
        {users.length ? (
          <ul className="grid gap-4 lg:grid-cols-2">
            {users.map((user) => (
              <li className="rounded-2xl border border-white bg-white p-5 shadow-card" key={user.id}>
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0">
                    <h3 className="truncate font-semibold text-ink">{user.display_name}</h3>
                    <p className="mt-1 truncate text-sm text-ink/65">{user.email ?? "No email available"}</p>
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-3 py-1 text-xs font-semibold ${
                      user.status === "active"
                        ? "bg-forest/10 text-forest"
                        : "bg-amber-100 text-amber-900"
                    }`}
                  >
                    {user.status}
                  </span>
                </div>
                <p className="mt-3 text-xs text-ink/55">
                  Added {new Intl.DateTimeFormat("en", { dateStyle: "medium" }).format(new Date(user.created_at))}
                </p>
                <UserManagementControls
                  assignedRoles={assignmentsByUser.get(user.id) ?? []}
                  availableRoles={availableRoles}
                  canManageRoles={canManageUsers || canManageSensitive}
                  canManageStatus={canManageUsers}
                  status={user.status}
                  userId={user.id}
                />
              </li>
            ))}
          </ul>
        ) : (
          <p className="rounded-2xl border border-dashed border-ink/20 bg-white/70 p-6 text-sm text-ink/65">
            No platform accounts are available.
          </p>
        )}
      </section>
    </div>
  );
}
