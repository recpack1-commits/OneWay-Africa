"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import {
  assignUserRoleAction,
  inviteUserAction,
  removeUserRoleAction,
  setUserStatusAction,
  type UserManagementActionState,
} from "@/app/dashboard/users/actions";
import { AuthSubmitButton } from "@/components/auth/submit-button";

const initialState: UserManagementActionState = {};

type RoleOption = { id: string; name: string };
type AssignedRole = RoleOption & { code: string };

function ActionMessage({ state }: Readonly<{ state: UserManagementActionState }>) {
  if (!state.error && !state.message) return null;

  return (
    <p
      aria-live="polite"
      className={`mt-3 text-sm ${state.error ? "text-red-700" : "text-forest"}`}
      role={state.error ? "alert" : "status"}
    >
      {state.error ?? state.message}
    </p>
  );
}

function InlineSubmitButton({ children }: Readonly<{ children: string }>) {
  const { pending } = useFormStatus();

  return (
    <button
      className="text-sm font-semibold text-forest underline decoration-forest/30 underline-offset-4 hover:text-ink disabled:opacity-60"
      disabled={pending}
      type="submit"
    >
      {pending ? "Please wait…" : children}
    </button>
  );
}

function RemoveRoleButton({ roleName }: Readonly<{ roleName: string }>) {
  const { pending } = useFormStatus();

  return (
    <button
      aria-label={pending ? `Removing ${roleName} role` : `Remove ${roleName} role`}
      className="font-bold text-ink/60 hover:text-red-700 disabled:opacity-60"
      disabled={pending}
      type="submit"
    >
      {pending ? "…" : "×"}
    </button>
  );
}

function RoleRemovalControl({
  userId,
  role,
}: Readonly<{ userId: string; role: AssignedRole }>) {
  const [state, action] = useActionState(removeUserRoleAction, initialState);

  return (
    <span>
      <form action={action}>
        <input name="userId" type="hidden" value={userId} />
        <input name="roleId" type="hidden" value={role.id} />
        <RemoveRoleButton roleName={role.name} />
      </form>
      <ActionMessage state={state} />
    </span>
  );
}

export function InviteUserForm({ roles }: Readonly<{ roles: RoleOption[] }>) {
  const [state, action] = useActionState(inviteUserAction, initialState);

  return (
    <form action={action} className="grid gap-4 rounded-2xl border border-ink/10 bg-white p-5 sm:grid-cols-2">
      <label className="grid gap-2 text-sm font-medium text-ink">
        Full name
        <input
          autoComplete="name"
          className="min-h-11 rounded-xl border border-ink/15 px-3 font-normal"
          maxLength={120}
          name="displayName"
          required
        />
      </label>
      <label className="grid gap-2 text-sm font-medium text-ink">
        Email address
        <input
          autoComplete="email"
          className="min-h-11 rounded-xl border border-ink/15 px-3 font-normal"
          name="email"
          required
          type="email"
        />
      </label>
      <label className="grid gap-2 text-sm font-medium text-ink">
        Initial role
        <select
          className="min-h-11 rounded-xl border border-ink/15 bg-white px-3 font-normal"
          defaultValue=""
          name="roleId"
          required
        >
          <option disabled value="">
            Choose a role
          </option>
          {roles.map((role) => (
            <option key={role.id} value={role.id}>
              {role.name}
            </option>
          ))}
        </select>
      </label>
      <div className="flex items-end">
        <AuthSubmitButton>Send invitation</AuthSubmitButton>
      </div>
      <div className="sm:col-span-2">
        <ActionMessage state={state} />
      </div>
    </form>
  );
}

export function UserManagementControls({
  userId,
  status,
  assignedRoles,
  availableRoles,
  canManageRoles,
  canManageStatus,
}: Readonly<{
  userId: string;
  status: "active" | "inactive" | "suspended" | "invited";
  assignedRoles: AssignedRole[];
  availableRoles: RoleOption[];
  canManageRoles: boolean;
  canManageStatus: boolean;
}>) {
  const [statusState, statusAction] = useActionState(setUserStatusAction, initialState);
  const [assignState, assignAction] = useActionState(assignUserRoleAction, initialState);

  if (!canManageRoles && !canManageStatus) return null;

  const assignedRoleIds = new Set(assignedRoles.map((role) => role.id));
  const unassignedRoles = availableRoles.filter((role) => !assignedRoleIds.has(role.id));
  const removableRoleIds = new Set(availableRoles.map((role) => role.id));

  return (
    <div className="mt-4 border-t border-ink/10 pt-4">
      <p className="text-xs font-semibold uppercase tracking-wide text-ink/55">Assigned roles</p>
      <ul className="mt-2 flex flex-wrap gap-2">
        {assignedRoles.length ? (
          assignedRoles.map((role) => (
            <li
              className="flex items-center gap-2 rounded-full bg-sand px-3 py-1 text-xs font-medium text-ink"
              key={role.id}
            >
              {role.name}
              {canManageRoles && removableRoleIds.has(role.id) && (
                <RoleRemovalControl role={role} userId={userId} />
              )}
            </li>
          ))
        ) : (
          <li className="text-sm text-ink/60">No roles assigned</li>
        )}
      </ul>

      {canManageRoles && unassignedRoles.length > 0 && (
        <form action={assignAction} className="mt-3 flex flex-wrap gap-2">
          <input name="userId" type="hidden" value={userId} />
          <label className="sr-only" htmlFor={`role-${userId}`}>
            Add role
          </label>
          <select
            className="min-h-10 rounded-xl border border-ink/15 bg-white px-3 text-sm"
            defaultValue=""
            id={`role-${userId}`}
            name="roleId"
            required
          >
            <option disabled value="">
              Add a role
            </option>
            {unassignedRoles.map((role) => (
              <option key={role.id} value={role.id}>
                {role.name}
              </option>
            ))}
          </select>
          <AuthSubmitButton>Assign role</AuthSubmitButton>
        </form>
      )}
      {canManageRoles && <ActionMessage state={assignState} />}

      {canManageStatus && status !== "invited" && (
        <form action={statusAction} className="mt-4">
          <input name="userId" type="hidden" value={userId} />
          <input name="status" type="hidden" value={status === "active" ? "inactive" : "active"} />
          <InlineSubmitButton>
            {status === "active" ? "Deactivate account" : "Activate account"}
          </InlineSubmitButton>
          <ActionMessage state={statusState} />
        </form>
      )}
    </div>
  );
}
