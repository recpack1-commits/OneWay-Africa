import { randomUUID } from "node:crypto";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AdjustmentCreateForm, AdjustmentDecisionControls, DisbursementResolutionControls, ExpenseReviewControls, OfficeDisbursementForm, OwnDisbursementControls, OwnExpenseControls } from "@/components/dashboard/finance-forms";
import { ExpenseEditor } from "@/components/dashboard/expense-editor";
import { createExpenseAction, updateExpenseAction } from "@/app/dashboard/finance/actions";
import { getServerAuthorization } from "@/lib/authorization";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";

type SearchParams = Record<string, string | string[] | undefined>;
type Period = Database["public"]["Tables"]["reporting_periods"]["Row"];
type Expense = Database["public"]["Tables"]["expenses"]["Row"];
type Disbursement = Database["public"]["Tables"]["disbursements"]["Row"];
type Adjustment = Database["public"]["Tables"]["financial_adjustments"]["Row"];

const PAGE_SIZE = 25;
const MAX_PAGE_SIZE = 100;
const views = ["summary", "expenses", "review", "disbursements", "adjustments"] as const;
const statuses = [
  "draft",
  "submitted",
  "queried",
  "approved",
  "rejected",
  "cancelled",
  "awaiting_confirmation",
  "partially_confirmed",
  "confirmed",
  "disputed",
  "settled_short",
  "reconciliation_required",
  "pending",
];

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function validDate(value: string | undefined): value is string {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value;
}

function validUuid(value: string | undefined): value is string {
  return Boolean(value && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value));
}

function formatAmount(amount: number | null, currency: string) {
  if (amount === null) return "—";
  return new Intl.NumberFormat("en-GH", {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

function formatGhs(amount: number | null, rate: number | null) {
  if (amount === null || rate === null) return "—";
  return formatAmount(Math.round((amount * rate + Number.EPSILON) * 100) / 100, "GHS");
}

function formatExchangeRate(
  currency: string,
  rate: number | null,
  rateDate: string | null,
  source: string | null,
) {
  if (currency === "GHS") return "GHS native amount; reporting rate 1.0";
  if (rate === null || !rateDate || !source) return "FX rate metadata unavailable";
  return `Rate ${rate} · ${rateDate} · ${source}`;
}

function queryString(params: URLSearchParams) {
  const value = params.toString();
  return value ? `?${value}` : "";
}

function SearchFilters({
  periods,
  selectedPeriod,
  fullRead,
  missionaries,
  currentMissionaryId,
  selectedMissionaryId,
  categories,
  view,
  status,
  pageSize,
  currency,
  categoryId,
  dateFrom,
  dateTo,
}: {
  periods: Period[];
  selectedPeriod: string;
  fullRead: boolean;
  missionaries: Array<{ id: string; display_name: string }>;
  currentMissionaryId: string | null;
  selectedMissionaryId: string;
  categories: Array<{ id: string; name: string }>;
  view: string;
  status: string;
  pageSize: number;
  currency: string;
  categoryId: string;
  dateFrom: string;
  dateTo: string;
}) {
  return (
    <form className="grid gap-3 rounded-2xl border border-ink/10 bg-white p-4 sm:grid-cols-2 lg:grid-cols-4" method="get">
      <input name="view" type="hidden" value={view} />
      <label className="space-y-1 text-xs"><span className="font-semibold">Reporting period (2027+)</span><select className="w-full rounded-xl border-ink/15 text-sm" defaultValue={selectedPeriod} name="periodId"><option value="">Choose period</option>{periods.map((period) => <option key={period.id} value={period.id}>{period.label}</option>)}</select></label>
      {fullRead && (
        <label className="space-y-1 text-xs"><span className="font-semibold">Missionary</span><select className="w-full rounded-xl border-ink/15 text-sm" defaultValue={selectedMissionaryId} name="missionaryId"><option value="">All / choose for balance</option>{missionaries.map((missionary) => <option key={missionary.id} value={missionary.id}>{missionary.display_name}</option>)}</select></label>
      )}
      {!fullRead && currentMissionaryId && <input name="missionaryId" type="hidden" value={currentMissionaryId} />}
      <label className="space-y-1 text-xs"><span className="font-semibold">Status</span><select className="w-full rounded-xl border-ink/15 text-sm" defaultValue={status} name="status"><option value="">All statuses</option>{statuses.map((item) => <option key={item} value={item}>{item.replaceAll("_", " ")}</option>)}</select></label>
      {(view === "expenses" || view === "review") && (
        <label className="space-y-1 text-xs"><span className="font-semibold">Line category</span><select className="w-full rounded-xl border-ink/15 text-sm" defaultValue={categoryId} name="categoryId"><option value="">All categories</option>{categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
      )}
      <label className="space-y-1 text-xs"><span className="font-semibold">Currency</span><input className="w-full rounded-xl border-ink/15 text-sm uppercase" defaultValue={currency} maxLength={3} name="currency" placeholder="All currencies" /></label>
      <label className="space-y-1 text-xs"><span className="font-semibold">Date from</span><input className="w-full rounded-xl border-ink/15 text-sm" defaultValue={dateFrom} name="dateFrom" type="date" /></label>
      <label className="space-y-1 text-xs"><span className="font-semibold">Date to</span><input className="w-full rounded-xl border-ink/15 text-sm" defaultValue={dateTo} name="dateTo" type="date" /></label>
      <label className="space-y-1 text-xs"><span className="font-semibold">Rows per page</span><select className="w-full rounded-xl border-ink/15 text-sm" defaultValue={pageSize} name="pageSize"><option value="25">25</option><option value="50">50</option><option value="100">100</option></select></label>
      <div className="flex items-end gap-3"><button className="rounded-xl bg-forest px-4 py-2 text-sm font-semibold text-white" type="submit">Apply filters</button><Link className="text-sm text-ink/60 underline" href={`/dashboard/finance?view=${view}`}>Clear</Link></div>
    </form>
  );
}

function Pagination({
  total,
  page,
  view,
  selectedPeriod,
  status,
  currency,
  categoryId,
  dateFrom,
  dateTo,
  missionaryId,
  pageSize,
}: {
  total: number;
  page: number;
  view: string;
  selectedPeriod: string;
  status: string;
  currency: string;
  categoryId: string;
  dateFrom: string;
  dateTo: string;
  missionaryId: string;
  pageSize: number;
}) {
  const pages = Math.ceil(total / pageSize);
  if (pages <= 1) return <p className="text-xs text-ink/55">Showing {total} record{total === 1 ? "" : "s"} · {pageSize} per page</p>;
  const makeHref = (nextPage: number) => {
    const params = new URLSearchParams({ view, page: String(nextPage), pageSize: String(pageSize) });
    if (selectedPeriod) params.set("periodId", selectedPeriod);
    if (status) params.set("status", status);
    if (currency) params.set("currency", currency);
    if (categoryId) params.set("categoryId", categoryId);
    if (dateFrom) params.set("dateFrom", dateFrom);
    if (dateTo) params.set("dateTo", dateTo);
    if (missionaryId) params.set("missionaryId", missionaryId);
    return `/dashboard/finance${queryString(params)}`;
  };
  return (
    <nav aria-label="Finance results pages" className="flex items-center justify-between gap-3 text-sm">
      <span className="text-xs text-ink/55">{total} records · {pageSize} per page (maximum {MAX_PAGE_SIZE})</span>
      <div className="flex gap-2">
        {page > 1 && <Link className="rounded-lg border border-ink/15 px-3 py-1.5" href={makeHref(page - 1)}>Previous</Link>}
        <span className="px-2 py-1.5">Page {page} of {pages}</span>
        {page < pages && <Link className="rounded-lg border border-ink/15 px-3 py-1.5" href={makeHref(page + 1)}>Next</Link>}
      </div>
    </nav>
  );
}

export default async function FinancePage({
  searchParams,
}: Readonly<{ searchParams: Promise<SearchParams> }>) {
  const authorization = await getServerAuthorization();
  if (!authorization) redirect("/sign-in");
  if (!authorization.profile || authorization.profile.status !== "active") redirect("/dashboard");

  const permissions = authorization.permissions;
  const fullRead = permissions.has("financial.read");
  const canManage = permissions.has("financial.manage");
  const ownExpenseAccess = permissions.has("financial.expenses.own_manage");
  const ownConfirmationAccess = permissions.has("financial.disbursements.own_confirm");
  const officeCreateAccess = permissions.has("financial.disbursements.create");
  const officeEvidenceAccess = permissions.has("financial.disbursements.evidence");
  if (!fullRead && !ownExpenseAccess && !ownConfirmationAccess && !officeCreateAccess && !officeEvidenceAccess) {
    redirect("/dashboard");
  }

  const params = await searchParams;
  const requestedView = first(params.view);
  const view = views.includes(requestedView as (typeof views)[number])
    ? requestedView!
    : canManage
      ? "summary"
      : ownExpenseAccess || ownConfirmationAccess
        ? "summary"
        : "disbursements";
  const permittedView = view === "review" && !canManage
    ? "expenses"
    : view === "adjustments" && !fullRead && !ownExpenseAccess && !ownConfirmationAccess
      ? "disbursements"
      : view === "expenses" && !fullRead && !ownExpenseAccess
        ? "disbursements"
        : view === "disbursements" && !fullRead && !ownConfirmationAccess && !officeCreateAccess && !officeEvidenceAccess
          ? "expenses"
          : view;
  if (permittedView !== view) redirect(`/dashboard/finance?view=${permittedView}`);

  const supabase = await createSupabaseServerClient();
  const [periodResult, categoryResult] = await Promise.all([
    supabase.from("reporting_periods").select("*").gte("year", 2027).order("start_date", { ascending: false }).limit(500),
    supabase.from("expense_categories").select("id,name").eq("is_active", true).order("name"),
  ]);
  if (periodResult.error || categoryResult.error) {
    return <FinanceLoadError message="The finance schema is unavailable. Apply the Stage 3 migrations in Supabase SQL Editor, then retry." />;
  }
  const periods = periodResult.data;
  const categories = categoryResult.data;
  const requestedPeriodId = first(params.periodId);
  const selectedPeriod = periods.find((period) => period.id === requestedPeriodId) ?? periods[0] ?? null;
  const periodId = selectedPeriod?.id ?? "";
  const requestedPageSize = Number(first(params.pageSize) ?? String(PAGE_SIZE));
  const pageSize = Number.isSafeInteger(requestedPageSize) && requestedPageSize > 0
    ? Math.min(requestedPageSize, MAX_PAGE_SIZE)
    : PAGE_SIZE;
  const pageNumber = Number(first(params.page) ?? "1");
  const page = Number.isSafeInteger(pageNumber) && pageNumber > 0 ? Math.min(pageNumber, 10_000) : 1;
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;
  const requestedStatus = first(params.status) ?? "";
  const status = statuses.includes(requestedStatus) ? requestedStatus : "";
  const currencyInput = (first(params.currency) ?? "").toUpperCase();
  const currency = /^[A-Z]{3}$/.test(currencyInput) ? currencyInput : "";
  const dateFrom = validDate(first(params.dateFrom)) ? first(params.dateFrom)! : "";
  const dateTo = validDate(first(params.dateTo)) ? first(params.dateTo)! : "";
  if (dateFrom && dateTo && dateFrom > dateTo) {
    return <FinanceLoadError message="The date range is invalid: Date from must not be after Date to." />;
  }
  const selectedCategory = first(params.categoryId);
  const categoryId = validUuid(selectedCategory) ? selectedCategory : "";

  let ownMissionaryId: string | null = null;
  if (!fullRead && (ownExpenseAccess || ownConfirmationAccess)) {
    const { data: missionary, error } = await supabase
      .from("missionaries")
      .select("id")
      .eq("app_user_id", authorization.userId)
      .eq("status", "active")
      .maybeSingle();
    if (error) return <FinanceLoadError message="Unable to load your linked missionary profile." />;
    ownMissionaryId = missionary?.id ?? null;
  }

  let recipientOptions: Array<{ id: string; display_name: string }> = [];
  if (fullRead || officeCreateAccess) {
    const { data, error } = await supabase.rpc("list_financial_missionary_recipients");
    if (error) return <FinanceLoadError message="Unable to load authorized active missionary recipients." />;
    recipientOptions = data;
  }
  const selectedMissionaryId = fullRead
    ? validUuid(first(params.missionaryId)) ? first(params.missionaryId)! : ""
    : ownMissionaryId ?? "";

  let balance: Database["public"]["Functions"]["get_financial_period_balance"]["Returns"][number] | null = null;
  if (periodId && selectedMissionaryId) {
    const { data, error } = await supabase.rpc("get_financial_period_balance", {
      p_missionary_id: selectedMissionaryId,
      p_reporting_period_id: periodId,
    });
    if (error) return <FinanceLoadError message="Unable to calculate the selected missionary's 2027+ balance." />;
    balance = data[0] ?? null;
  }

  let expenses: Expense[] = [];
  let expenseCount = 0;
  let disbursements: Disbursement[] = [];
  let disbursementCount = 0;
  let adjustments: Adjustment[] = [];
  let adjustmentCount = 0;
  let expenseLines: Database["public"]["Tables"]["expense_lines"]["Row"][] = [];
  let expenseReceipts: Database["public"]["Tables"]["expense_receipts"]["Row"][] = [];
  let disbursementReceipts: Database["public"]["Tables"]["disbursement_receipts"]["Row"][] = [];
  let confirmations: Database["public"]["Tables"]["disbursement_confirmations"]["Row"][] = [];
  let fileAssets: Database["public"]["Tables"]["file_assets"]["Row"][] = [];

  if (periodId && (permittedView === "expenses" || permittedView === "review")) {
    let categoryExpenseIds: string[] | null = null;
    if (categoryId) {
      const categoryMatches: string[] = [];
      let offset = 0;
      while (offset < 25_000) {
        const { data, error } = await supabase
          .from("expense_lines")
          .select("expense_id")
          .eq("expense_category_id", categoryId)
          .range(offset, offset + 999);
        if (error) return <FinanceLoadError message="Unable to filter expenses by item-line category." />;
        categoryMatches.push(...data.map((line) => line.expense_id));
        if (data.length < 1000) break;
        offset += data.length;
      }
      if (categoryMatches.length >= 25_000) {
        return <FinanceLoadError message="This category has too many matches for a precise filter. Add a narrower date or status filter." />;
      }
      categoryExpenseIds = Array.from(new Set(categoryMatches));
    }

    let request = supabase.from("expenses").select("*", { count: "exact" })
      .eq("reporting_period_id", periodId)
      .order("expense_date", { ascending: false })
      .order("created_at", { ascending: false })
      .range(from, to);
    if (fullRead) {
      if (selectedMissionaryId) request = request.eq("missionary_id", selectedMissionaryId);
    } else if (ownMissionaryId) {
      request = request.eq("missionary_id", ownMissionaryId);
    } else {
      request = request.eq("missionary_id", "00000000-0000-0000-0000-000000000000");
    }
    if (permittedView === "review") request = request.eq("status", "submitted");
    else if (status) request = request.eq("status", status as Expense["status"]);
    if (currency) request = request.eq("currency", currency);
    if (dateFrom) request = request.gte("expense_date", dateFrom);
    if (dateTo) request = request.lte("expense_date", dateTo);
    if (categoryExpenseIds) request = categoryExpenseIds.length ? request.in("id", categoryExpenseIds) : request.eq("id", "00000000-0000-0000-0000-000000000000");
    const { data, count, error } = await request;
    if (error) return <FinanceLoadError message="Unable to load expenses. Check finance access and migration status." />;
    expenses = data;
    expenseCount = count ?? 0;
    const expenseIds = expenses.map((expense) => expense.id);
    if (expenseIds.length) {
      const [lineResult, receiptResult] = await Promise.all([
        supabase.from("expense_lines").select("*").in("expense_id", expenseIds).order("line_number"),
        supabase.from("expense_receipts").select("*").in("expense_id", expenseIds).order("uploaded_at", { ascending: false }),
      ]);
      if (lineResult.error || receiptResult.error) return <FinanceLoadError message="Unable to load expense lines or receipt history." />;
      expenseLines = lineResult.data;
      expenseReceipts = receiptResult.data;
    }
  }

  if (periodId && permittedView === "disbursements") {
    let request = supabase.from("disbursements").select("*", { count: "exact" })
      .eq("reporting_period_id", periodId)
      .order("sent_date", { ascending: false })
      .order("created_at", { ascending: false })
      .range(from, to);
    if (fullRead) {
      if (selectedMissionaryId) request = request.eq("missionary_id", selectedMissionaryId);
    } else if (ownMissionaryId && ownConfirmationAccess) {
      request = request.eq("missionary_id", ownMissionaryId);
    } else if (officeCreateAccess) {
      request = request.eq("created_by", authorization.userId);
    } else {
      request = request.eq("id", "00000000-0000-0000-0000-000000000000");
    }
    if (status) request = request.eq("status", status as Disbursement["status"]);
    if (currency) request = request.eq("currency", currency);
    if (dateFrom) request = request.gte("sent_date", dateFrom);
    if (dateTo) request = request.lte("sent_date", dateTo);
    const { data, count, error } = await request;
    if (error) return <FinanceLoadError message="Unable to load disbursements. Check finance access and migration status." />;
    disbursements = data;
    disbursementCount = count ?? 0;
    const ids = disbursements.map((disbursement) => disbursement.id);
    if (ids.length) {
      const [confirmationResult, receiptResult] = await Promise.all([
        supabase.from("disbursement_confirmations").select("*").in("disbursement_id", ids).order("created_at", { ascending: false }),
        supabase.from("disbursement_receipts").select("*").in("disbursement_id", ids).order("uploaded_at", { ascending: false }),
      ]);
      if (confirmationResult.error || receiptResult.error) return <FinanceLoadError message="Unable to load disbursement confirmation history." />;
      confirmations = confirmationResult.data;
      disbursementReceipts = receiptResult.data;
    }
  }

  if (periodId && permittedView === "adjustments") {
    let request = supabase.from("financial_adjustments").select("*", { count: "exact" })
      .eq("reporting_period_id", periodId)
      .order("created_at", { ascending: false })
      .range(from, to);
    if (!fullRead && ownMissionaryId) request = request.eq("missionary_id", ownMissionaryId);
    if (status) request = request.eq("status", status as Adjustment["status"]);
    if (currency) request = request.eq("currency", currency);
    if (dateFrom) request = request.gte("adjustment_date", dateFrom);
    if (dateTo) request = request.lte("adjustment_date", dateTo);
    const { data, count, error } = await request;
    if (error) return <FinanceLoadError message="Unable to load adjustments." />;
    adjustments = data;
    adjustmentCount = count ?? 0;
  }

  const visibleFileIds = Array.from(new Set([
    ...expenseReceipts.map((receipt) => receipt.file_asset_id),
    ...disbursementReceipts.map((receipt) => receipt.file_asset_id),
  ]));
  if (visibleFileIds.length) {
    const { data, error } = await supabase.from("file_assets").select("*").in("id", visibleFileIds);
    if (error) return <FinanceLoadError message="Unable to load receipt metadata." />;
    fileAssets = data;
  }
  const fileById = new Map(fileAssets.map((asset) => [asset.id, asset]));
  const signedUrlByAsset = new Map<string, string>();
  let signedUrlError = false;
  if (visibleFileIds.length) {
    const admin = createSupabaseAdminClient();
    const signedResults = await Promise.all(fileAssets.map(async (asset) => {
      const { data, error } = await admin.storage.from(asset.bucket_id).createSignedUrl(asset.object_path, 60);
      if (error) {
        signedUrlError = true;
        return null;
      }
      return [asset.id, data.signedUrl] as const;
    }));
    for (const result of signedResults) if (result) signedUrlByAsset.set(result[0], result[1]);
  }

  const linesByExpense = new Map<string, typeof expenseLines>();
  for (const line of expenseLines) {
    const lines = linesByExpense.get(line.expense_id) ?? [];
    lines.push(line);
    linesByExpense.set(line.expense_id, lines);
  }
  const receiptsByExpense = new Map<string, typeof expenseReceipts>();
  for (const receipt of expenseReceipts) {
    const receipts = receiptsByExpense.get(receipt.expense_id) ?? [];
    receipts.push(receipt);
    receiptsByExpense.set(receipt.expense_id, receipts);
  }
  const confirmationsByDisbursement = new Map<string, typeof confirmations>();
  for (const confirmation of confirmations) {
    const events = confirmationsByDisbursement.get(confirmation.disbursement_id) ?? [];
    events.push(confirmation);
    confirmationsByDisbursement.set(confirmation.disbursement_id, events);
  }

  const tabParams = (nextView: string) => {
    const next = new URLSearchParams({ view: nextView });
    if (periodId) next.set("periodId", periodId);
    next.set("pageSize", String(pageSize));
    if (selectedMissionaryId && fullRead) next.set("missionaryId", selectedMissionaryId);
    return `/dashboard/finance${queryString(next)}`;
  };
  const currentPageCount = permittedView === "expenses" || permittedView === "review"
    ? expenseCount
    : permittedView === "disbursements"
      ? disbursementCount
      : permittedView === "adjustments"
        ? adjustmentCount
        : 0;

  return (
    <div className="space-y-7">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.18em] text-leaf">Finance · 2027+ only</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-ink">Financial management</h1>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-ink/65">
            Native amounts remain unchanged; GHS values use the transaction&apos;s recorded exchange rate. No historical records are imported here.
          </p>
        </div>
        <Link className="rounded-full border border-ink/15 px-4 py-2 text-sm font-semibold text-ink" href="/dashboard#finance">
          Dashboard Finance anchor
        </Link>
      </header>
      {signedUrlError && (
        <p className="rounded-xl border border-amber-900/15 bg-amber-50 p-3 text-sm text-amber-900" role="status">
          Some receipt download links could not be generated. Refresh to retry; receipt metadata remains available where your role permits.
        </p>
      )}
      {!fullRead && (ownExpenseAccess || ownConfirmationAccess) && !ownMissionaryId && (
        <FinanceLoadError message="No active missionary profile is linked to this account. Contact an administrator before using own-finance actions." />
      )}

      <nav aria-label="Finance views" className="flex flex-wrap gap-2">
        {(fullRead ? ["summary", "expenses", ...(canManage ? ["review"] : []), "disbursements", "adjustments"] : [
          ...((ownExpenseAccess || ownConfirmationAccess) ? ["summary"] : []),
          ...(ownExpenseAccess ? ["expenses"] : []),
          ...(ownConfirmationAccess || officeCreateAccess || officeEvidenceAccess ? ["disbursements"] : []),
          ...(ownExpenseAccess || ownConfirmationAccess ? ["adjustments"] : []),
        ]).map((item) => (
          <Link
            aria-current={permittedView === item ? "page" : undefined}
            className={`rounded-full px-4 py-2 text-sm font-semibold ${permittedView === item ? "bg-forest text-white" : "bg-white text-ink/70 hover:bg-sand"}`}
            href={tabParams(item)}
            key={item}
          >
            {item === "review" ? "Review queue" : item[0].toUpperCase() + item.slice(1)}
          </Link>
        ))}
      </nav>

      <SearchFilters
        categories={categories}
        categoryId={categoryId}
        currency={currency}
        currentMissionaryId={ownMissionaryId}
        dateFrom={dateFrom}
        dateTo={dateTo}
        fullRead={fullRead}
        missionaries={recipientOptions}
        pageSize={pageSize}
        periods={periods}
        selectedMissionaryId={selectedMissionaryId}
        selectedPeriod={periodId}
        status={status}
        view={permittedView}
      />

      {!periods.length && (
        <section className="rounded-2xl border border-ink/10 bg-white p-5 text-sm text-ink/70">
          No 2027+ reporting periods are available. Create periods through the approved finance administration process before recording transactions.
        </section>
      )}
      {periods.length > 0 && !periodId && <FinanceLoadError message="Select a 2027+ reporting period to view financial records." />}

      {permittedView === "summary" && periodId && (
        <section aria-label="Balances and reimbursement" className="space-y-4">
          {balance ? (
            <>
              <h2 className="text-xl font-semibold text-ink">Selected missionary balance · {selectedPeriod?.label}</h2>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
                <BalanceCard label="Confirmed received net" value={balance.confirmed_received_net_ghs} />
                <BalanceCard label="Approved expenses" value={balance.approved_expenses_ghs} />
                <BalanceCard label="Carry-forward" value={balance.carry_forward_ghs} />
                <BalanceCard label="Available balance" value={balance.available_balance_ghs} />
                <BalanceCard label="Reimbursement due" value={balance.reimbursement_due_ghs} />
              </div>
            </>
          ) : (
            <section className="rounded-2xl border border-ink/10 bg-white p-5">
              <h2 className="font-semibold text-ink">Balances and reimbursement</h2>
              <p className="mt-2 text-sm text-ink/65">
                {fullRead ? "Choose a missionary filter to calculate a period balance." : "No active missionary profile is linked to this account."}
              </p>
            </section>
          )}
          {fullRead && (
            <div className="grid gap-3 sm:grid-cols-2">
              <Link className="rounded-2xl border border-ink/10 bg-white p-5 font-semibold text-ink" href={tabParams("expenses")}>Open expenses and item lines →</Link>
              <Link className="rounded-2xl border border-ink/10 bg-white p-5 font-semibold text-ink" href={tabParams("disbursements")}>Open disbursements and confirmations →</Link>
            </div>
          )}
        </section>
      )}

      {(permittedView === "expenses" || permittedView === "review") && periodId && (
        <section className="space-y-4">
          {permittedView === "review" ? (
            <h2 className="text-xl font-semibold text-ink">Financial Director review queue</h2>
          ) : (
            <h2 className="text-xl font-semibold text-ink">Expenses and itemised lines</h2>
          )}
          {ownExpenseAccess && periods.length > 0 && (
            <details className="rounded-2xl border border-ink/10 bg-sand/45 p-4">
              <summary className="cursor-pointer font-semibold text-ink">Create an expense draft</summary>
              <div className="mt-4">
                <ExpenseEditor
                  action={createExpenseAction}
                  categories={categories}
                  initial={{
                    reportingPeriodId: periodId,
                    expenseDate: "",
                    currency: "GHS",
                    exchangeRate: "1",
                    exchangeRateDate: "",
                    exchangeRateSource: "",
                    description: "",
                    lines: [{ expense_category_id: "", description: "", amount: "" }],
                  }}
                  initialKey={randomUUID()}
                  periods={periods.map(({ id, label }) => ({ id, label }))}
                  retryScope="finance:create-expense"
                />
              </div>
            </details>
          )}
          {expenses.length ? expenses.map((expense) => {
            const lineRows = linesByExpense.get(expense.id) ?? [];
            const receiptRows = receiptsByExpense.get(expense.id) ?? [];
            const activeReceipts = receiptRows.filter((receipt) =>
              !receiptRows.some((candidate) => candidate.supersedes_receipt_id === receipt.id),
            );
            const visibleOwnExpense = ownExpenseAccess && expense.missionary_id === ownMissionaryId;
            return (
              <article className="rounded-2xl border border-ink/10 bg-white p-5" key={expense.id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-ink/50">{expense.status.replaceAll("_", " ")}</p>
                    <h3 className="mt-1 font-semibold text-ink">{expense.description}</h3>
                    <p className="mt-1 text-sm text-ink/65">{expense.expense_date} · {selectedPeriod?.label}</p>
                  </div>
                  <div className="text-right">
                    <p className="font-semibold text-ink">{formatAmount(expense.amount, expense.currency)}</p>
                    <p className="text-sm text-ink/60">GHS report: {formatGhs(expense.amount, expense.exchange_rate_to_ghs)}</p>
                    <p className="mt-1 max-w-md text-xs text-ink/50">{formatExchangeRate(expense.currency, expense.exchange_rate_to_ghs, expense.exchange_rate_date, expense.exchange_rate_source)}</p>
                  </div>
                </div>
                {expense.over_funds_flag && (
                  <p className="mt-3 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">
                    Exceeds confirmed received funds: {expense.over_funds_note}
                  </p>
                )}
                <div className="mt-4 overflow-x-auto">
                  <table className="w-full min-w-[32rem] text-left text-sm">
                    <thead><tr className="border-b border-ink/10 text-xs uppercase text-ink/50"><th className="py-2 pr-3">Line</th><th className="py-2 pr-3">Category</th><th className="py-2 pr-3">Description</th><th className="py-2 text-right">Native amount</th></tr></thead>
                    <tbody>{lineRows.map((line) => (
                      <tr className="border-b border-ink/5" key={line.id}>
                        <td className="py-2 pr-3">{line.line_number}</td>
                        <td className="py-2 pr-3">{categories.find((category) => category.id === line.expense_category_id)?.name ?? "Category unavailable"}</td>
                        <td className="py-2 pr-3">{line.description}</td>
                        <td className="py-2 text-right">{formatAmount(line.amount, expense.currency)}</td>
                      </tr>
                    ))}</tbody>
                  </table>
                </div>
                <div className="mt-4 space-y-2">
                  <h4 className="text-sm font-semibold text-ink">Receipt history</h4>
                  {receiptRows.length ? receiptRows.map((receipt) => {
                    const asset = fileById.get(receipt.file_asset_id);
                    const superseded = receiptRows.some((candidate) => candidate.supersedes_receipt_id === receipt.id);
                    return (
                      <p className="text-sm text-ink/70" key={receipt.id}>
                        {asset && signedUrlByAsset.has(asset.id)
                          ? <a className="underline" href={signedUrlByAsset.get(asset.id)} rel="noreferrer" target="_blank">{asset.original_filename}</a>
                          : asset?.original_filename ?? "Receipt metadata is not visible to this role"}
                        {superseded ? " · replaced (history retained)" : " · active"}
                      </p>
                    );
                  }) : <p className="text-sm text-ink/55">No receipts attached.</p>}
                </div>
                {permittedView === "review" && <ExpenseReviewControls expenseId={expense.id} />}
                {visibleOwnExpense && (
                  <div className="mt-4 space-y-3">
                    {["draft", "queried"].includes(expense.status) && (
                      <details className="rounded-xl bg-sand/45 p-3">
                        <summary className="cursor-pointer text-sm font-semibold text-ink">Edit expense draft</summary>
                        <div className="mt-3">
                          <ExpenseEditor
                            action={updateExpenseAction}
                            categories={categories}
                            initial={{
                              expenseId: expense.id,
                              reportingPeriodId: expense.reporting_period_id,
                              expenseDate: expense.expense_date,
                              currency: expense.currency,
                              exchangeRate: expense.exchange_rate_to_ghs?.toString() ?? "",
                              exchangeRateDate: expense.exchange_rate_date ?? "",
                              exchangeRateSource: expense.exchange_rate_source ?? "",
                              description: expense.description,
                              lines: lineRows.map((line) => ({
                                expense_category_id: line.expense_category_id,
                                description: line.description,
                                amount: line.amount.toString(),
                              })).length ? lineRows.map((line) => ({
                                expense_category_id: line.expense_category_id,
                                description: line.description,
                                amount: line.amount.toString(),
                              })) : [{ expense_category_id: "", description: "", amount: "" }],
                            }}
                            initialKey={randomUUID()}
                            periods={periods.map(({ id, label }) => ({ id, label }))}
                            retryScope={`finance:edit-expense:${expense.id}`}
                          />
                        </div>
                      </details>
                    )}
                    <OwnExpenseControls
                      activeReceipts={activeReceipts.map((receipt, index) => ({ id: receipt.id, label: `Receipt ${index + 1}` }))}
                      expenseId={expense.id}
                      initialUploadKey={randomUUID()}
                      status={expense.status}
                    />
                  </div>
                )}
              </article>
            );
          }) : <p className="rounded-2xl border border-ink/10 bg-white p-5 text-sm text-ink/65">No expenses match these filters.</p>}
        </section>
      )}

      {permittedView === "disbursements" && periodId && (
        <section className="space-y-4">
          <h2 className="text-xl font-semibold text-ink">Disbursements and confirmations</h2>
          {officeCreateAccess && (
            <OfficeDisbursementForm
              initialKey={randomUUID()}
              periods={periods.map(({ id, label }) => ({ id, label }))}
              recipients={recipientOptions}
            />
          )}
          {disbursements.length ? disbursements.map((disbursement) => {
            const receiptRows = disbursementReceipts.filter((receipt) => receipt.disbursement_id === disbursement.id);
            return (
              <article className="rounded-2xl border border-ink/10 bg-white p-5" key={disbursement.id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-ink/50">{disbursement.status.replaceAll("_", " ")}</p>
                    <h3 className="mt-1 font-semibold text-ink">{disbursement.reference}</h3>
                    <p className="mt-1 text-sm text-ink/65">{disbursement.sent_date} · {disbursement.payment_method}</p>
                    {disbursement.notes && <p className="mt-1 text-sm text-ink/65">{disbursement.notes}</p>}
                  </div>
                  <div className="text-right">
                    <p className="font-semibold text-ink">{formatAmount(disbursement.amount_sent, disbursement.currency)} sent</p>
                    <p className="text-sm text-ink/60">Received: {formatAmount(disbursement.effective_amount_received, disbursement.currency)}</p>
                    <p className="text-sm text-ink/60">GHS report: {formatGhs(disbursement.effective_amount_received, disbursement.exchange_rate_to_ghs)}</p>
                    <p className="mt-1 max-w-md text-xs text-ink/50">{formatExchangeRate(disbursement.currency, disbursement.exchange_rate_to_ghs, disbursement.exchange_rate_date, disbursement.exchange_rate_source)}</p>
                  </div>
                </div>
                {disbursement.settlement_note && <p className="mt-3 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">Settled-short note: {disbursement.settlement_note}</p>}
                <div className="mt-4 space-y-2">
                  <h4 className="text-sm font-semibold text-ink">Confirmation events</h4>
                  {(confirmationsByDisbursement.get(disbursement.id) ?? []).length ? (confirmationsByDisbursement.get(disbursement.id) ?? []).map((event) => (
                    <p className="text-sm text-ink/70" key={event.id}>
                      {event.decision === "dispute" ? "Dispute" : `${event.amount_mode ?? "mode unavailable"} confirmation: ${formatAmount(event.amount_received, disbursement.currency)}`}
                      {event.received_date ? ` · ${event.received_date}` : ""}
                      {event.notes ? ` · ${event.notes}` : ""}
                    </p>
                  )) : <p className="text-sm text-ink/55">No confirmation event is visible.</p>}
                </div>
                {receiptRows.length > 0 && (
                  <div className="mt-3 space-y-1">
                    <h4 className="text-sm font-semibold text-ink">Payment evidence</h4>
                    {receiptRows.map((receipt) => {
                      const asset = fileById.get(receipt.file_asset_id);
                      return <p className="text-sm text-ink/70" key={receipt.id}>{asset && signedUrlByAsset.has(asset.id) ? <a className="underline" href={signedUrlByAsset.get(asset.id)} rel="noreferrer" target="_blank">{asset.original_filename}</a> : asset?.original_filename ?? "Evidence metadata is not visible to this role"}</p>;
                    })}
                  </div>
                )}
                {ownConfirmationAccess && ownMissionaryId === disbursement.missionary_id && (
                  <OwnDisbursementControls
                    createdByCurrentUser={false}
                    disbursementId={disbursement.id}
                    initialConfirmationKey={randomUUID()}
                    initialDisputeKey={randomUUID()}
                    initialEvidenceKey={randomUUID()}
                  />
                )}
                {officeEvidenceAccess && authorization.userId === disbursement.created_by && (
                  <OwnDisbursementControls
                    createdByCurrentUser
                    disbursementId={disbursement.id}
                    initialConfirmationKey={randomUUID()}
                    initialDisputeKey={randomUUID()}
                    initialEvidenceKey={randomUUID()}
                  />
                )}
                {canManage && (
                  <DisbursementResolutionControls disbursementId={disbursement.id} />
                )}
              </article>
            );
          }) : <p className="rounded-2xl border border-ink/10 bg-white p-5 text-sm text-ink/65">No disbursements match these filters.</p>}
        </section>
      )}

      {permittedView === "adjustments" && periodId && (
        <section className="space-y-4">
          <h2 className="text-xl font-semibold text-ink">Adjustments, reversals, carry-forward</h2>
          {canManage && <AdjustmentCreateForm initialKey={randomUUID()} periods={periods.map(({ id, label }) => ({ id, label }))} />}
          {adjustments.length ? adjustments.map((adjustment) => (
            <article className="rounded-2xl border border-ink/10 bg-white p-5" key={adjustment.id}>
              <div className="flex flex-wrap justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-ink/50">{adjustment.status} · {adjustment.adjustment_type.replaceAll("_", " ")}</p>
                  <p className="mt-1 font-semibold text-ink">{adjustment.reason}</p>
                  <p className="mt-1 text-sm text-ink/60">{adjustment.adjustment_date ?? "Date unavailable"} · {adjustment.currency}</p>
                </div>
                <div className="text-right">
                  <p className="font-semibold text-ink">{formatAmount(adjustment.amount, adjustment.currency)}</p>
                  <p className="text-sm text-ink/60">GHS report: {formatGhs(adjustment.amount, adjustment.exchange_rate_to_ghs)}</p>
                  <p className="mt-1 max-w-md text-xs text-ink/50">{formatExchangeRate(adjustment.currency, adjustment.exchange_rate_to_ghs, adjustment.exchange_rate_date, adjustment.exchange_rate_source)}</p>
                </div>
              </div>
              {canManage && adjustment.status === "pending" && (
                <AdjustmentDecisionControls
                  adjustmentId={adjustment.id}
                  currentUserId={authorization.userId}
                  requesterId={adjustment.requested_by}
                />
              )}
            </article>
          )) : <p className="rounded-2xl border border-ink/10 bg-white p-5 text-sm text-ink/65">No adjustments match these filters.</p>}
        </section>
      )}

      {["expenses", "review", "disbursements", "adjustments"].includes(permittedView) && periodId && (
        <Pagination
          categoryId={categoryId}
          currency={currency}
          dateFrom={dateFrom}
          dateTo={dateTo}
          missionaryId={selectedMissionaryId}
          page={page}
          pageSize={pageSize}
          selectedPeriod={periodId}
          status={status}
          total={currentPageCount}
          view={permittedView}
        />
      )}
    </div>
  );
}

function BalanceCard({ label, value }: Readonly<{ label: string; value: number }>) {
  return (
    <article className="rounded-2xl border border-ink/10 bg-white p-4">
      <p className="text-xs font-semibold uppercase tracking-wide text-ink/55">{label}</p>
      <p className="mt-2 text-lg font-semibold text-ink">{formatAmount(value, "GHS")}</p>
    </article>
  );
}

function FinanceLoadError({ message }: Readonly<{ message: string }>) {
  return <section className="rounded-2xl border border-red-900/15 bg-red-50 p-5 text-sm text-red-900" role="alert">{message}</section>;
}
