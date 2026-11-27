"use client";

import {
  approveAdjustmentAction,
  cancelExpenseAction,
  confirmDisbursementAction,
  createAdjustmentAction,
  createDisbursementAction,
  rejectAdjustmentAction,
  resolveDisbursementAction,
  reviewExpenseAction,
  submitExpenseAction,
  uploadDisbursementEvidenceAction,
  uploadExpenseReceiptAction,
} from "@/app/dashboard/finance/actions";
import {
  FinanceActionForm,
  FinanceSubmitButton,
} from "@/components/dashboard/finance-action-form";

const fieldClass = "w-full rounded-xl border-ink/15 text-sm";

export function ReceiptUploadForm({
  recordId,
  kind,
  receipts = [],
  initialKey,
}: Readonly<{
  recordId: string;
  kind: "expense" | "disbursement";
  receipts?: Array<{ id: string; label: string }>;
  initialKey: string;
}>) {
  const isExpense = kind === "expense";
  return (
    <FinanceActionForm
      action={isExpense ? uploadExpenseReceiptAction : uploadDisbursementEvidenceAction}
      className="space-y-2 rounded-xl border border-ink/10 bg-sand/40 p-3"
      initialKey={initialKey}
      retryScope={`finance:upload:${kind}:${recordId}`}
    >
      <input name={isExpense ? "expenseId" : "disbursementId"} type="hidden" value={recordId} />
      {isExpense && receipts.length > 0 && (
        <label className="block space-y-1 text-xs">
          <span className="font-medium">Replace active receipt (optional)</span>
          <select className={fieldClass} name="supersedesReceiptId">
            <option value="">Add as an additional receipt</option>
            {receipts.map((receipt) => <option key={receipt.id} value={receipt.id}>{receipt.label}</option>)}
          </select>
        </label>
      )}
      <label className="block space-y-1 text-xs">
        <span className="font-medium">{isExpense ? "Expense receipt" : "Payment evidence"} (JPEG, PNG, WebP or PDF; max 5 MB)</span>
        <input
          accept=".jpg,.jpeg,.png,.webp,.pdf,image/jpeg,image/png,image/webp,application/pdf"
          className="block w-full text-sm"
          name="file"
          required
          type="file"
        />
      </label>
      <FinanceSubmitButton>{isExpense ? "Upload verified receipt" : "Upload payment evidence"}</FinanceSubmitButton>
    </FinanceActionForm>
  );
}

export function OwnExpenseControls({
  expenseId,
  status,
  activeReceipts,
  initialUploadKey,
}: Readonly<{
  expenseId: string;
  status: string;
  activeReceipts: Array<{ id: string; label: string }>;
  initialUploadKey: string;
}>) {
  if (!["draft", "queried"].includes(status)) return null;
  return (
    <div className="mt-4 space-y-3">
      <ReceiptUploadForm
        initialKey={initialUploadKey}
        kind="expense"
        receipts={activeReceipts}
        recordId={expenseId}
      />
      <FinanceActionForm action={submitExpenseAction}>
        <input name="expenseId" type="hidden" value={expenseId} />
        <label className="block space-y-1 text-xs">
          <span className="font-medium">Note required if expenses exceed confirmed received funds</span>
          <textarea className={fieldClass} maxLength={1000} name="overFundsNote" rows={2} />
        </label>
        <FinanceSubmitButton>Submit expense</FinanceSubmitButton>
      </FinanceActionForm>
      <FinanceActionForm action={cancelExpenseAction} className="rounded-xl border border-ink/10 bg-white p-3">
        <input name="expenseId" type="hidden" value={expenseId} />
        <FinanceSubmitButton>Cancel unapproved expense</FinanceSubmitButton>
      </FinanceActionForm>
    </div>
  );
}

export function ExpenseReviewControls({ expenseId }: Readonly<{ expenseId: string }>) {
  return (
    <FinanceActionForm action={reviewExpenseAction} className="mt-3 space-y-2 rounded-xl border border-ink/10 bg-sand/50 p-3">
      <input name="expenseId" type="hidden" value={expenseId} />
      <label className="block space-y-1 text-xs">
        <span className="font-medium">Review decision</span>
        <select className={fieldClass} name="decision" required>
          <option value="approve">Approve</option>
          <option value="query">Query / request clarification</option>
          <option value="reject">Reject</option>
        </select>
      </label>
      <label className="block space-y-1 text-xs">
        <span className="font-medium">Comments (required for query or rejection)</span>
        <textarea className={fieldClass} maxLength={2000} name="comments" rows={2} />
      </label>
      <FinanceSubmitButton>Save review decision</FinanceSubmitButton>
    </FinanceActionForm>
  );
}

export function OfficeDisbursementForm({
  periods,
  recipients,
  initialKey,
}: Readonly<{
  periods: Array<{ id: string; label: string }>;
  recipients: Array<{ id: string; display_name: string }>;
  initialKey: string;
}>) {
  if (!periods.length || !recipients.length) {
    return <p className="rounded-xl bg-sand p-4 text-sm text-ink/70">A 2027+ reporting period and active missionary are required before recording a disbursement.</p>;
  }
  return (
    <FinanceActionForm
      action={createDisbursementAction}
      className="grid gap-3 rounded-2xl border border-ink/10 bg-white p-5 sm:grid-cols-2"
      initialKey={initialKey}
      retryScope="finance:create-disbursement"
    >
      <h3 className="font-semibold text-ink sm:col-span-2">Record disbursement</h3>
      <label className="space-y-1 text-sm"><span className="font-medium">Reference</span><input className={fieldClass} maxLength={100} name="reference" required /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Missionary</span><select className={fieldClass} name="missionaryId" required>{recipients.map((recipient) => <option key={recipient.id} value={recipient.id}>{recipient.display_name}</option>)}</select></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Reporting period (2027+)</span><select className={fieldClass} name="reportingPeriodId" required>{periods.map((period) => <option key={period.id} value={period.id}>{period.label}</option>)}</select></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Amount sent</span><input className={fieldClass} min="0.01" name="amountSent" required step="0.01" type="number" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Sent date</span><input className={fieldClass} name="sentDate" required type="date" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Payment method</span><input className={fieldClass} maxLength={100} name="paymentMethod" required /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Currency</span><input className={`${fieldClass} uppercase`} defaultValue="GHS" maxLength={3} minLength={3} name="currency" required /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Exchange rate to GHS (GHS = 1)</span><input className={fieldClass} inputMode="decimal" name="exchangeRate" placeholder="1.0 for GHS" required step="0.00000001" type="number" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Rate date (non-GHS)</span><input className={fieldClass} name="exchangeRateDate" type="date" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Rate source (non-GHS)</span><input className={fieldClass} maxLength={500} name="exchangeRateSource" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Transaction reference (optional)</span><input className={fieldClass} maxLength={200} name="transactionReference" /></label>
      <label className="space-y-1 text-sm sm:col-span-2"><span className="font-medium">Notes</span><textarea className={fieldClass} maxLength={2000} name="notes" rows={2} /></label>
      <div className="sm:col-span-2"><FinanceSubmitButton>Save disbursement</FinanceSubmitButton></div>
    </FinanceActionForm>
  );
}

export function OwnDisbursementControls({
  disbursementId,
  createdByCurrentUser,
  initialConfirmationKey,
  initialDisputeKey,
  initialEvidenceKey,
}: Readonly<{
  disbursementId: string;
  createdByCurrentUser: boolean;
  initialConfirmationKey: string;
  initialDisputeKey: string;
  initialEvidenceKey: string;
}>) {
  return (
    <div className="mt-4 space-y-3">
      {!createdByCurrentUser && (
        <>
          <FinanceActionForm
            action={confirmDisbursementAction}
            className="grid gap-2 rounded-xl border border-ink/10 bg-white p-3 sm:grid-cols-2"
            initialKey={initialConfirmationKey}
            retryScope={`finance:confirm:${disbursementId}`}
          >
            <input name="disbursementId" type="hidden" value={disbursementId} />
            <input name="decision" type="hidden" value="confirm" />
            <label className="space-y-1 text-xs"><span className="font-medium">Received amount (native currency)</span><input className={fieldClass} min="0.01" name="amountReceived" required step="0.01" type="number" /></label>
            <label className="space-y-1 text-xs"><span className="font-medium">Received date</span><input className={fieldClass} name="receivedDate" required type="date" /></label>
            <label className="space-y-1 text-xs"><span className="font-medium">Confirmation mode</span><select className={fieldClass} name="amountMode"><option value="incremental">Incremental amount</option><option value="cumulative">Cumulative total</option></select></label>
            <label className="space-y-1 text-xs"><span className="font-medium">Notes (optional)</span><input className={fieldClass} maxLength={2000} name="notes" /></label>
            <div className="sm:col-span-2"><FinanceSubmitButton>Confirm received funds</FinanceSubmitButton></div>
          </FinanceActionForm>
          <FinanceActionForm
            action={confirmDisbursementAction}
            className="space-y-2 rounded-xl border border-amber-900/15 bg-amber-50 p-3"
            initialKey={initialDisputeKey}
            retryScope={`finance:dispute:${disbursementId}`}
          >
            <input name="disbursementId" type="hidden" value={disbursementId} />
            <input name="decision" type="hidden" value="dispute" />
            <label className="block space-y-1 text-xs"><span className="font-medium">Explain the discrepancy</span><textarea className={fieldClass} maxLength={2000} name="notes" required rows={2} /></label>
            <FinanceSubmitButton>Dispute this disbursement</FinanceSubmitButton>
          </FinanceActionForm>
        </>
      )}
      {createdByCurrentUser && (
        <ReceiptUploadForm
          initialKey={initialEvidenceKey}
          kind="disbursement"
          recordId={disbursementId}
        />
      )}
    </div>
  );
}

export function DisbursementResolutionControls({
  disbursementId,
  adjustmentId,
}: Readonly<{ disbursementId: string; adjustmentId?: string }>) {
  return (
    <FinanceActionForm action={resolveDisbursementAction} className="mt-3 space-y-2 rounded-xl border border-ink/10 bg-sand/50 p-3">
      <input name="disbursementId" type="hidden" value={disbursementId} />
      <label className="block space-y-1 text-xs"><span className="font-medium">Financial Director resolution</span><select className={fieldClass} name="resolutionType"><option value="resolve_dispute">Clear dispute</option><option value="settle_short">Approve settled-short</option><option value="reconcile_overpayment">Reconcile overpayment</option></select></label>
      <label className="block space-y-1 text-xs"><span className="font-medium">Notes (required)</span><textarea className={fieldClass} maxLength={2000} name="notes" required rows={2} /></label>
      <label className="block space-y-1 text-xs"><span className="font-medium">Approved adjustment ID (required for overpayment)</span><input className={fieldClass} defaultValue={adjustmentId} name="financialAdjustmentId" /></label>
      <FinanceSubmitButton>Save Financial Director resolution</FinanceSubmitButton>
    </FinanceActionForm>
  );
}

export function AdjustmentCreateForm({
  periods,
  initialKey,
}: Readonly<{ periods: Array<{ id: string; label: string }>; initialKey: string }>) {
  if (!periods.length) return null;
  return (
    <FinanceActionForm
      action={createAdjustmentAction}
      className="grid gap-3 rounded-2xl border border-ink/10 bg-white p-5 sm:grid-cols-2"
      initialKey={initialKey}
      retryScope="finance:create-adjustment"
    >
      <h3 className="font-semibold text-ink sm:col-span-2">Request adjustment or carry-forward</h3>
      <label className="space-y-1 text-sm"><span className="font-medium">Adjustment type</span><select className={fieldClass} name="adjustmentType"><option value="correction">Correction</option><option value="reimbursement">Reimbursement</option><option value="reversal">Reversal</option><option value="carry_forward">Carry-forward</option><option value="other">Other</option></select></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Target record type</span><select className={fieldClass} name="targetType"><option value="disbursement">Disbursement</option><option value="expense">Expense</option></select></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Target record ID</span><input className={fieldClass} name="targetId" required /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Reporting period</span><select className={fieldClass} name="reportingPeriodId">{periods.map((period) => <option key={period.id} value={period.id}>{period.label}</option>)}</select></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Amount (signed, native currency)</span><input className={fieldClass} name="amount" required step="0.01" type="number" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Currency</span><input className={`${fieldClass} uppercase`} defaultValue="GHS" maxLength={3} minLength={3} name="currency" required /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Exchange rate to GHS (GHS = 1)</span><input className={fieldClass} name="exchangeRate" placeholder="1.0 for GHS" required step="0.00000001" type="number" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Rate date (non-GHS)</span><input className={fieldClass} name="exchangeRateDate" type="date" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Rate source (non-GHS)</span><input className={fieldClass} maxLength={500} name="exchangeRateSource" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Adjustment date</span><input className={fieldClass} name="adjustmentDate" required type="date" /></label>
      <label className="space-y-1 text-sm"><span className="font-medium">Reversal of adjustment ID (reversal only)</span><input className={fieldClass} name="reversalOfId" /></label>
      <label className="space-y-1 text-sm sm:col-span-2"><span className="font-medium">Reason</span><textarea className={fieldClass} maxLength={2000} name="reason" required rows={2} /></label>
      <div className="sm:col-span-2"><FinanceSubmitButton>Submit adjustment request</FinanceSubmitButton></div>
    </FinanceActionForm>
  );
}

export function AdjustmentDecisionControls({
  adjustmentId,
  requesterId,
  currentUserId,
}: Readonly<{ adjustmentId: string; requesterId: string; currentUserId: string }>) {
  if (requesterId === currentUserId) return <p className="mt-2 text-sm text-amber-800">You requested this adjustment and cannot decide it.</p>;
  return (
    <div className="mt-3 flex flex-wrap items-start gap-3">
      <FinanceActionForm action={approveAdjustmentAction} className="rounded-xl border border-ink/10 bg-white p-3">
        <input name="adjustmentId" type="hidden" value={adjustmentId} />
        <FinanceSubmitButton>Approve adjustment</FinanceSubmitButton>
      </FinanceActionForm>
      <FinanceActionForm action={rejectAdjustmentAction} className="space-y-2 rounded-xl border border-ink/10 bg-white p-3">
        <input name="adjustmentId" type="hidden" value={adjustmentId} />
        <label className="block space-y-1 text-xs"><span className="font-medium">Rejection reason</span><textarea className={fieldClass} maxLength={2000} name="reason" required rows={2} /></label>
        <FinanceSubmitButton>Reject adjustment</FinanceSubmitButton>
      </FinanceActionForm>
    </div>
  );
}
