"use client";

import { useActionState } from "react";
import { updatePasswordAction } from "@/lib/actions/auth";
import { AuthSubmitButton } from "@/components/auth/submit-button";

export function UpdatePasswordForm() {
  const [state, formAction] = useActionState(updatePasswordAction, {});

  return (
    <form action={formAction} className="mt-7 space-y-5">
      <label className="block">
        <span className="mb-2 block text-sm font-semibold text-ink">New password</span>
        <input
          autoComplete="new-password"
          className="w-full rounded-xl border-ink/15 bg-white px-4 py-3 text-ink shadow-sm focus:border-forest focus:ring-forest"
          minLength={8}
          name="password"
          required
          type="password"
        />
      </label>
      <label className="block">
        <span className="mb-2 block text-sm font-semibold text-ink">Confirm new password</span>
        <input
          autoComplete="new-password"
          className="w-full rounded-xl border-ink/15 bg-white px-4 py-3 text-ink shadow-sm focus:border-forest focus:ring-forest"
          minLength={8}
          name="confirmPassword"
          required
          type="password"
        />
      </label>
      {state.error && (
        <p role="alert" className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-800">
          {state.error}
        </p>
      )}
      <AuthSubmitButton>Update password</AuthSubmitButton>
    </form>
  );
}
