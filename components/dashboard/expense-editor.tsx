"use client";

import { useState } from "react";
import {
  FinanceActionForm,
  FinanceSubmitButton,
} from "@/components/dashboard/finance-action-form";
import type { FinanceActionState } from "@/app/dashboard/finance/actions";

type ExpenseLineInput = {
  expense_category_id: string;
  description: string;
  amount: string;
};

type FinanceAction = (
  previous: FinanceActionState,
  formData: FormData,
) => Promise<FinanceActionState>;

export function ExpenseEditor({
  action,
  categories,
  periods,
  initial,
  initialKey,
  retryScope,
}: Readonly<{
  action: FinanceAction;
  categories: Array<{ id: string; name: string }>;
  periods: Array<{ id: string; label: string }>;
  initial: {
    expenseId?: string;
    reportingPeriodId: string;
    expenseDate: string;
    currency: string;
    exchangeRate: string;
    exchangeRateDate: string;
    exchangeRateSource: string;
    description: string;
    lines: ExpenseLineInput[];
  };
  initialKey: string;
  retryScope: string;
}>) {
  const [lines, setLines] = useState(initial.lines);

  function updateLine(index: number, patch: Partial<ExpenseLineInput>) {
    setLines((current) => current.map((line, position) =>
      position === index ? { ...line, ...patch } : line,
    ));
  }

  return (
    <FinanceActionForm
      action={action}
      className="space-y-4 rounded-2xl border border-ink/10 bg-white p-5"
      initialKey={initialKey}
      retryScope={retryScope}
    >
      {initial.expenseId && <input name="expenseId" type="hidden" value={initial.expenseId} />}
      <h3 className="font-semibold text-ink">
        {initial.expenseId ? "Edit draft expense" : "Create expense draft"}
      </h3>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="space-y-1 text-sm">
          <span className="font-medium">Reporting period (2027+)</span>
          <select
            className="w-full rounded-xl border-ink/15"
            defaultValue={initial.reportingPeriodId}
            name="reportingPeriodId"
            required
          >
            {periods.map((period) => <option key={period.id} value={period.id}>{period.label}</option>)}
          </select>
        </label>
        <label className="space-y-1 text-sm">
          <span className="font-medium">Expense date</span>
          <input className="w-full rounded-xl border-ink/15" defaultValue={initial.expenseDate} name="expenseDate" required type="date" />
        </label>
        <label className="space-y-1 text-sm">
          <span className="font-medium">Currency (ISO 4217)</span>
          <input className="w-full rounded-xl border-ink/15 uppercase" defaultValue={initial.currency} maxLength={3} minLength={3} name="currency" required />
        </label>
        <label className="space-y-1 text-sm">
          <span className="font-medium">Exchange rate to GHS (GHS = 1)</span>
          <input className="w-full rounded-xl border-ink/15" defaultValue={initial.exchangeRate} inputMode="decimal" name="exchangeRate" placeholder="1.0 for GHS" required step="0.00000001" type="number" />
        </label>
        <label className="space-y-1 text-sm">
          <span className="font-medium">Rate date (required for non-GHS)</span>
          <input className="w-full rounded-xl border-ink/15" defaultValue={initial.exchangeRateDate} name="exchangeRateDate" type="date" />
        </label>
        <label className="space-y-1 text-sm">
          <span className="font-medium">Rate source (required for non-GHS)</span>
          <input className="w-full rounded-xl border-ink/15" defaultValue={initial.exchangeRateSource} maxLength={500} name="exchangeRateSource" />
        </label>
      </div>
      <label className="block space-y-1 text-sm">
        <span className="font-medium">Expense summary</span>
        <textarea className="w-full rounded-xl border-ink/15" defaultValue={initial.description} maxLength={2000} name="description" required rows={2} />
      </label>
      <fieldset className="space-y-3">
        <legend className="font-semibold text-ink">Itemised expense lines</legend>
        {lines.map((line, index) => (
          <div className="grid gap-2 rounded-xl bg-sand/60 p-3 sm:grid-cols-[1fr_1.2fr_8rem_auto]" key={index}>
            <label className="space-y-1 text-xs">
              <span className="font-medium">Category</span>
              <select
                className="w-full rounded-lg border-ink/15 text-sm"
                onChange={(event) => updateLine(index, { expense_category_id: event.target.value })}
                required
                value={line.expense_category_id}
              >
                <option value="">Choose category</option>
                {categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
              </select>
            </label>
            <label className="space-y-1 text-xs">
              <span className="font-medium">Line description</span>
              <input
                className="w-full rounded-lg border-ink/15 text-sm"
                maxLength={500}
                onChange={(event) => updateLine(index, { description: event.target.value })}
                required
                value={line.description}
              />
            </label>
            <label className="space-y-1 text-xs">
              <span className="font-medium">Native amount</span>
              <input
                className="w-full rounded-lg border-ink/15 text-sm"
                min="0.01"
                onChange={(event) => updateLine(index, { amount: event.target.value })}
                required
                step="0.01"
                type="number"
                value={line.amount}
              />
            </label>
            <button
              aria-label={`Remove line ${index + 1}`}
              className="self-end rounded-lg border border-ink/15 px-3 py-2 text-sm disabled:opacity-40"
              disabled={lines.length === 1}
              onClick={() => setLines((current) => current.filter((_, position) => position !== index))}
              type="button"
            >
              Remove
            </button>
          </div>
        ))}
        <input name="lines" type="hidden" value={JSON.stringify(lines.map((line) => ({
          expense_category_id: line.expense_category_id,
          description: line.description,
          amount: Number(line.amount),
        })))} />
        <button
          className="rounded-xl border border-ink/15 px-3 py-2 text-sm font-medium"
          disabled={lines.length >= 100}
          onClick={() => setLines((current) => [...current, {
            expense_category_id: "",
            description: "",
            amount: "",
          }])}
          type="button"
        >
          Add line
        </button>
      </fieldset>
      <FinanceSubmitButton>{initial.expenseId ? "Save draft changes" : "Save expense draft"}</FinanceSubmitButton>
    </FinanceActionForm>
  );
}
