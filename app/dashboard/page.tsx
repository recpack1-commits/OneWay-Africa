import Link from "next/link";
import { redirect } from "next/navigation";
import { getServerAuthorization } from "@/lib/authorization";

const modules = [
  {
    permission: "users.read",
    id: "users",
    title: "User management",
    description: "Review platform accounts and manage access according to your permissions.",
    href: "/dashboard/users",
  },
  {
    permission: "missionaries.read_all",
    id: "missionaries",
    title: "Missionary directory",
    description: "Access missionary records and field assignments.",
  },
  {
    permission: "field.reports.read",
    id: "field-reports",
    title: "Field reports",
    description: "Work with ministry reporting available to your role.",
  },
  {
    permission: "inventory.read",
    id: "inventory",
    title: "Inventory",
    description: "Review and manage inventory according to your assigned role.",
  },
  {
    permission: "financial.read",
    id: "finance",
    title: "Finance",
    description: "Access confidential financial records as a Financial Director.",
  },
];

export default async function DashboardPage() {
  const authorization = await getServerAuthorization();
  if (!authorization) redirect("/sign-in");

  const visibleModules = modules.filter(({ permission }) =>
    authorization.permissions.has(permission),
  );
  const hasScopedFinance = [
    "financial.expenses.own_manage",
    "financial.disbursements.own_confirm",
    "financial.disbursements.create",
    "financial.disbursements.evidence",
  ].some((permission) => authorization.permissions.has(permission));
  const dashboardModules = [
    ...visibleModules,
    ...(!authorization.permissions.has("financial.read") && hasScopedFinance
      ? [{
          id: "my-finance",
          title: authorization.permissions.has("financial.disbursements.create")
            ? "Disbursement workspace"
            : "My finance",
          description: authorization.permissions.has("financial.disbursements.create")
            ? "Record disbursements and attach payment evidence for records you create."
            : "Manage your own eligible expenses and confirm disbursements assigned to you.",
          href: "/dashboard/finance",
        }]
      : []),
  ];

  return (
    <div className="space-y-8">
      <section className="rounded-3xl border border-white/80 bg-white/85 p-6 shadow-card sm:p-10">
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-leaf">2027 operations</p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-ink">
          Welcome, {authorization.profile?.display_name ?? "team member"}
        </h1>
        <p className="mt-3 max-w-2xl text-sm leading-6 text-ink/70">
          Your workspace is tailored to the permissions assigned to your account.
        </p>
        {authorization.roles.length > 0 && (
          <ul aria-label="Your roles" className="mt-5 flex flex-wrap gap-2">
            {authorization.roles.map((role) => (
              <li
                className="rounded-full bg-forest/10 px-3 py-1 text-xs font-semibold text-forest"
                key={role.code}
              >
                {role.name}
              </li>
            ))}
          </ul>
        )}
      </section>

      {dashboardModules.length > 0 ? (
        <section aria-label="Available work areas" className="grid gap-4 sm:grid-cols-2">
          {dashboardModules.map((module) => {
            const content = (
              <>
                <h2 className="font-semibold text-ink">{module.title}</h2>
                <p className="mt-2 text-sm leading-6 text-ink/65">{module.description}</p>
                {module.id === "finance" && (
                  <Link className="mt-4 inline-flex text-sm font-semibold text-forest underline" href="/dashboard/finance">
                    Open Finance workspace →
                  </Link>
                )}
              </>
            );
            const className =
              "block rounded-2xl border border-white bg-white/85 p-6 shadow-card transition hover:-translate-y-0.5 hover:shadow-lg";

            return module.href ? (
              <Link className={className} href={module.href} key={module.id}>
                {content}
              </Link>
            ) : (
              <article className={className} id={module.id} key={module.id}>
                {content}
              </article>
            );
          })}
        </section>
      ) : (
        <section className="rounded-2xl border border-white bg-white/85 p-6 shadow-card">
          <h2 className="font-semibold text-ink">No work areas assigned yet</h2>
          <p className="mt-2 text-sm leading-6 text-ink/65">
            Your account is active, but it does not have any enabled work-area permissions. Contact
            your platform administrator if you believe this is incorrect.
          </p>
        </section>
      )}
    </div>
  );
}
