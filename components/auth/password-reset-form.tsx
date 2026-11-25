"use client";

import { useActionState } from "react";
import { requestPasswordResetAction } from "@/lib/actions/auth";
import { AuthSubmitButton } from "@/components/auth/submit-button";

export function PasswordResetForm() {
  const [state, formAction] = useActionState(requestPasswordResetAction, {});

  return (
    <form action={formAction} className="mt-7 space-y-5">
      <label className="block">
        <span className="mb-2 block text-sm font-semibold text-ink">Email address</span>
        <input
          autoComplete="email"
          className="w-full rounded-xl border-ink/15 bg-white px-4 py-3 text-ink shadow-sm placeholder:text-ink/35 focus:border-forest focus:ring-forest"
          name="email"
          placeholder="name@example.com"
          required
          type="email"
        />
      </label>
      {state.error && (
        <p role="alert" className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-800">
          {state.error}
        </p>
      )}
      {state.message && (
        <p role="status" className="rounded-xl bg-emerald-50 px-4 py-3 text-sm text-forest">
          {state.message}
        </p>
      )}
      <AuthSubmitButton>Send recovery link</AuthSubmitButton>
    </form>
  );
}
