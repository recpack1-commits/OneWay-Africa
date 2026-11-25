"use client";

import { useFormStatus } from "react-dom";

export function AuthSubmitButton({ children }: Readonly<{ children: string }>) {
  const { pending } = useFormStatus();

  return (
    <button
      className="flex min-h-12 w-full items-center justify-center rounded-xl bg-forest px-5 py-3 text-sm font-semibold text-white transition hover:bg-ink disabled:cursor-not-allowed disabled:opacity-65"
      disabled={pending}
      type="submit"
    >
      {pending ? "Please wait…" : children}
    </button>
  );
}
