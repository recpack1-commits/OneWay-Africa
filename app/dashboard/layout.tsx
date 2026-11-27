import type { ReactNode } from "react";
import Link from "next/link";
import Image from "next/image";
import { redirect } from "next/navigation";
import { SignOutButton } from "@/components/auth/sign-out-button";
import { getServerAuthorization } from "@/lib/authorization";

const navigationItems = [
  { permission: "users.read", label: "Users", href: "/dashboard/users" },
  { permission: "missionaries.read_all", label: "Missionaries", href: "/dashboard#missionaries" },
  { permission: "field.reports.read", label: "Field reports", href: "/dashboard#field-reports" },
  { permission: "inventory.read", label: "Inventory", href: "/dashboard#inventory" },
  { permission: "financial.read", label: "Finance", href: "/dashboard#finance" },
];

export default async function DashboardLayout({ children }: Readonly<{ children: ReactNode }>) {
  const authorization = await getServerAuthorization();
  if (!authorization) redirect("/sign-in");

  const isActive = authorization.profile?.status === "active";

  return (
    <div className="min-h-screen">
      <header className="border-b border-ink/10 bg-white/80">
        <div className="mx-auto max-w-7xl px-5 py-4 sm:px-8 lg:px-12">
          <div className="flex items-center justify-between gap-4">
            <Link aria-label="OneWay Africa dashboard" className="flex items-center gap-3" href="/dashboard">
              <Image
                alt=""
                className="size-10 rounded-full"
                height={40}
                src="/icons/oneway-africa-mark.png"
                width={40}
              />
              <span>
                <span className="block text-sm font-extrabold uppercase tracking-[0.08em] text-ink sm:text-base">
                  ONEWAY AFRICA
                </span>
                <span className="block max-w-[12rem] text-[0.6rem] font-semibold uppercase leading-tight tracking-[0.1em] text-ink/60 sm:max-w-none sm:text-[0.65rem] sm:tracking-[0.13em]">
                  JFC &amp; BIBLEPLUS INVENTORY PLATFORM
                </span>
              </span>
            </Link>
            {isActive && (
              <div className="flex items-center gap-3">
                <span className="hidden max-w-48 truncate text-sm text-ink/70 sm:block">
                  {authorization.profile?.display_name}
                </span>
                <SignOutButton />
              </div>
            )}
          </div>
          {isActive && (
            <nav aria-label="Main navigation" className="mt-4 flex gap-2 overflow-x-auto pb-1">
              <Link
                className="shrink-0 rounded-full bg-sand px-4 py-2 text-sm font-semibold text-ink"
                href="/dashboard"
              >
                Overview
              </Link>
              {navigationItems
                .filter(({ permission }) => authorization.permissions.has(permission))
                .map(({ href, label }) => (
                  <Link
                    className="shrink-0 rounded-full px-4 py-2 text-sm font-medium text-ink/70 transition hover:bg-sand hover:text-ink"
                    href={href}
                    key={label}
                  >
                    {label}
                  </Link>
                ))}
            </nav>
          )}
        </div>
      </header>
      {isActive ? (
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
