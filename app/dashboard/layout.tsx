import type { ReactNode } from "react";
import { redirect } from "next/navigation";
import { SignOutButton } from "@/components/auth/sign-out-button";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function DashboardLayout({ children }: Readonly<{ children: ReactNode }>) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/sign-in");
  }

  const { data: appUser, error } = await supabase
    .from("app_users")
    .select("display_name, status")
    .eq("id", user.id)
    .maybeSingle();

  if (error) {
    throw new Error("Unable to verify your platform access. Please try again.");
  }

  return (
    <div className="min-h-screen">
      <header className="border-b border-ink/10 bg-white/80">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-5 py-4 sm:px-8 lg:px-12">
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-forest text-sm font-bold text-white">
              OA
            </span>
            <div>
              <p className="text-sm font-bold text-ink">OneWay Africa</p>
              <p className="text-xs text-ink/60">Ministry platform</p>
            </div>
          </div>
          {appUser?.status === "active" && (
            <div className="flex items-center gap-3">
              <span className="hidden max-w-48 truncate text-sm text-ink/70 sm:block">
                {appUser.display_name}
              </span>
              <SignOutButton />
            </div>
          )}
        </div>
      </header>
      {appUser?.status === "active" ? (
        <main className="mx-auto max-w-7xl px-5 py-8 sm:px-8 sm:py-12 lg:px-12">{children}</main>
      ) : (
        <main className="mx-auto max-w-2xl px-5 py-16 sm:px-8">
          <section className="rounded-3xl border border-white bg-white p-7 shadow-card sm:p-10">
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-leaf">Access restricted</p>
            <h1 className="mt-3 text-2xl font-semibold tracking-tight text-ink">
              Your account is not active
            </h1>
            <p className="mt-3 text-sm leading-6 text-ink/70">
              Your session is valid, but no active platform profile is available for this account.
              Please contact your platform administrator.
            </p>
            <div className="mt-6">
              <SignOutButton />
            </div>
          </section>
        </main>
      )}
    </div>
  );
}
