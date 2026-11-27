"use client";

import { useActionState, useEffect, useState, type FormEvent, type ReactNode } from "react";
import { useFormStatus } from "react-dom";
import type { FinanceActionState } from "@/app/dashboard/finance/actions";

type FinanceAction = (
  previous: FinanceActionState,
  formData: FormData,
) => Promise<FinanceActionState>;

function SubmitButton({ children }: Readonly<{ children: ReactNode }>) {
  const { pending } = useFormStatus();
  return (
    <button
      className="rounded-xl bg-forest px-4 py-2 text-sm font-semibold text-white transition hover:bg-forest/90 disabled:cursor-wait disabled:opacity-60"
      disabled={pending}
      type="submit"
    >
      {pending ? "Saving…" : children}
    </button>
  );
}

export function FinanceActionForm({
  action,
  children,
  className = "space-y-3 rounded-2xl border border-ink/10 bg-white p-4",
  initialKey,
  retryScope,
}: Readonly<{
  action: FinanceAction;
  children: ReactNode;
  className?: string;
  initialKey?: string;
  retryScope?: string;
}>) {
  const [state, formAction] = useActionState(action, {});
  const [key, setKey] = useState(initialKey ?? "");

  useEffect(() => {
    if (!retryScope || !initialKey) return;
    setKey(sessionStorage.getItem(retryScope) ?? initialKey);
  }, [initialKey, retryScope]);

  useEffect(() => {
    if (!state.success || !retryScope) return;
    sessionStorage.removeItem(retryScope);
    setKey(crypto.randomUUID());
  }, [retryScope, state]);

  function rememberRetryKey(event: FormEvent<HTMLFormElement>) {
    if (!retryScope || !key) return;
    const formData = new FormData(event.currentTarget);
    const value = formData.get("clientSubmissionId");
    if (typeof value === "string" && value) sessionStorage.setItem(retryScope, value);
  }

  function resetRetryKey() {
    if (retryScope) sessionStorage.removeItem(retryScope);
    setKey(crypto.randomUUID());
  }

  return (
    <form action={formAction} className={className} onSubmit={rememberRetryKey}>
      {retryScope && <input name="clientSubmissionId" type="hidden" value={key} />}
      {children}
      {state.error && <p className="text-sm font-medium text-red-700" role="alert">{state.error}</p>}
      {state.message && (
        <p className={`text-sm font-medium ${state.success ? "text-forest" : "text-ink/70"}`} role="status">
          {state.message}
        </p>
      )}
      {retryScope && !state.success && (
        <button className="text-xs font-medium text-ink/60 underline" onClick={resetRetryKey} type="button">
          Start a new retry key
        </button>
      )}
    </form>
  );
}

export function FinanceSubmitButton({ children }: Readonly<{ children: ReactNode }>) {
  return <SubmitButton>{children}</SubmitButton>;
}
