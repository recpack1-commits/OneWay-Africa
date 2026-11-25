"use server";

import { revalidatePath } from "next/cache";
import { requireAnyPermission, requirePermission } from "@/lib/authorization";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type UserManagementActionState = {
  error?: string;
  message?: string;
};

function getString(formData: FormData, key: string) {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function checkRoleAssignmentPermission(roleId: string, authorization: {
  userId: string;
  permissions: Set<string>;
}) {
  const supabase = await createSupabaseServerClient();
  const { data: rolePermissionLinks, error: rolePermissionsError } = await supabase
    .from("role_permissions")
    .select("permission_id")
    .eq("role_id", roleId);

  if (rolePermissionsError) {
    throw new Error("Unable to verify the selected role. Please try again.");
  }

  const permissionIds = rolePermissionLinks.map(({ permission_id }) => permission_id);
  if (!permissionIds.length) return null;

  const { data: sensitivePermissions, error: permissionsError } = await supabase
    .from("permissions")
    .select("id")
    .in("id", permissionIds)
    .eq("is_sensitive", true);

  if (permissionsError) {
    throw new Error("Unable to verify the selected role. Please try again.");
  }

  const canManageSensitive = authorization.permissions.has("financial.roles.manage");
  const canManageGeneral = authorization.permissions.has("users.manage");
  if (sensitivePermissions.length && !canManageSensitive) {
    return "Only a Financial Director can assign roles that grant confidential financial access.";
  }
  if (!sensitivePermissions.length && !canManageGeneral) {
    return "You do not have permission to assign this role.";
  }

  return null;
}

export async function inviteUserAction(
  _previousState: UserManagementActionState,
  formData: FormData,
): Promise<UserManagementActionState> {
  const authorization = await requireAnyPermission("users.manage", "financial.roles.manage");
  const displayName = getString(formData, "displayName");
  const email = getString(formData, "email").toLowerCase();
  const roleId = getString(formData, "roleId");

  if (!displayName || displayName.length > 120 || !email || !roleId) {
    return { error: "Enter a name, valid email address, and role." };
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !isUuid(roleId)) {
    return { error: "Enter a valid email address and select a valid role." };
  }

  const supabase = await createSupabaseServerClient();
  const { data: role, error: roleError } = await supabase
    .from("roles")
    .select("id")
    .eq("id", roleId)
    .maybeSingle();
  if (roleError) {
    throw new Error("Unable to verify the selected role. Please try again.");
  }
  if (!role) return { error: "That role is unavailable. Refresh the page and try again." };

  const roleAccessError = await checkRoleAssignmentPermission(role.id, authorization);
  if (roleAccessError) return { error: roleAccessError };

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (!siteUrl) {
    return { error: "User invitations are not configured. Contact your platform administrator." };
  }

  const admin = createSupabaseAdminClient();
  const { data: invitation, error: invitationError } = await admin.auth.admin.inviteUserByEmail(
    email,
    {
      data: { display_name: displayName },
      redirectTo: `${new URL(siteUrl).origin}/auth/callback?next=/update-password`,
    },
  );
  if (invitationError || !invitation.user) {
    return { error: "Unable to send the invitation. Check the email address and try again." };
  }

  const { error: assignmentError } = await supabase.from("user_roles").insert({
    user_id: invitation.user.id,
    role_id: role.id,
    assigned_by: authorization.userId,
  });
  if (assignmentError) {
    return {
      error:
        "The invitation was sent, but the role could not be assigned. The account remains inactive; retry the role assignment from the directory.",
    };
  }

  const { error: activationError } = await supabase
    .from("app_users")
    .update({ status: "active", deactivated_at: null, deactivated_by: null })
    .eq("id", invitation.user.id);
  if (activationError) {
    return {
      error:
        "The invitation and role were created, but the account could not be activated. It remains blocked until you retry.",
    };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/users");
  return { message: `Invitation sent to ${email}.` };
}

export async function assignUserRoleAction(
  _previousState: UserManagementActionState,
  formData: FormData,
): Promise<UserManagementActionState> {
  const authorization = await requireAnyPermission("users.manage", "financial.roles.manage");
  const userId = getString(formData, "userId");
  const roleId = getString(formData, "roleId");
  if (!isUuid(userId) || !isUuid(roleId)) return { error: "Select a valid user and role." };

  const supabase = await createSupabaseServerClient();
  const { data: role, error: roleError } = await supabase
    .from("roles")
    .select("id")
    .eq("id", roleId)
    .maybeSingle();
  if (roleError) throw new Error("Unable to verify the selected role. Please try again.");
  if (!role) return { error: "That role is unavailable. Refresh the page and try again." };

  const roleAccessError = await checkRoleAssignmentPermission(role.id, authorization);
  if (roleAccessError) return { error: roleAccessError };

  const { error } = await supabase.from("user_roles").insert({
    user_id: userId,
    role_id: role.id,
    assigned_by: authorization.userId,
  });
  if (error?.code === "23505") return { error: "That user already has this role." };
  if (error) return { error: "Unable to assign the role. Check your access and try again." };

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/users");
  return { message: "Role assigned." };
}

export async function removeUserRoleAction(
  _previousState: UserManagementActionState,
  formData: FormData,
): Promise<UserManagementActionState> {
  const authorization = await requireAnyPermission("users.manage", "financial.roles.manage");
  const userId = getString(formData, "userId");
  const roleId = getString(formData, "roleId");
  if (!isUuid(userId) || !isUuid(roleId)) return { error: "Select a valid user and role." };

  const supabase = await createSupabaseServerClient();
  const roleAccessError = await checkRoleAssignmentPermission(roleId, authorization);
  if (roleAccessError) return { error: roleAccessError };
  const { error } = await supabase
    .from("user_roles")
    .delete()
    .eq("user_id", userId)
    .eq("role_id", roleId);
  if (error) return { error: "Unable to remove the role. Check your access and try again." };

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/users");
  return { message: "Role removed." };
}

export async function setUserStatusAction(
  _previousState: UserManagementActionState,
  formData: FormData,
): Promise<UserManagementActionState> {
  const authorization = await requirePermission("users.manage");
  const userId = getString(formData, "userId");
  const status = getString(formData, "status");
  if (!isUuid(userId) || (status !== "active" && status !== "inactive")) {
    return { error: "Select a valid account and status." };
  }
  if (userId === authorization.userId && status !== "active") {
    return { error: "You cannot deactivate your own account." };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("app_users")
    .update({
      status,
      deactivated_at: status === "inactive" ? new Date().toISOString() : null,
      deactivated_by: status === "inactive" ? authorization.userId : null,
    })
    .eq("id", userId)
    .select("id")
    .maybeSingle();

  if (error) return { error: "Unable to update account status. Check your access and try again." };
  if (!data) return { error: "That account could not be found or is not available to you." };

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/users");
  return { message: status === "active" ? "Account activated." : "Account deactivated." };
}
