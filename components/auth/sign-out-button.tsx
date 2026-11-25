import { signOutAction } from "@/lib/actions/auth";

export function SignOutButton() {
  return (
    <form action={signOutAction}>
      <button
        className="rounded-lg border border-ink/15 px-3 py-2 text-sm font-semibold text-ink transition hover:border-forest hover:text-forest"
        type="submit"
      >
        Sign out
      </button>
    </form>
  );
}
