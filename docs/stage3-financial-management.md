# Stage 3 Financial Management

## Scope and current baseline

Stage 3 applies only to reporting periods in 2027 or later. Do not create test data,
invent financial records, or create 2026 historical records.

- Finance currently appears as the `#finance` dashboard anchor, shown with
  `financial.read`; there is no dedicated finance route.
- The dashboard redirects unauthenticated users to `/sign-in` and restricts inactive
  profiles. Preserve both guards.
- The Financial Director currently has `financial.read`, `financial.manage`, and
  `financial.roles.manage`. System Administrators, Office Staff, Missionaries, and
  Field Directors receive no financial permissions by default.
- Existing RLS allows financial-permission reads and limited own-record reads. There
  are no Stage 3 finance write policies. Do not broaden access by inference.
- The baseline schema has disbursement, confirmation, receipt, expense, review,
  adjustment, and reporting-period tables. Reporting periods constrain years to
  2027–2100.

## Approved 2027 financial rules

These are approved business rules for Stage 3. This document is a specification and
implementation plan, not an instruction to edit application code or migrations.

| Item | Approved rule |
| --- | --- |
| Expense categories | Use exactly these 11 categories: Fuel; Vehicle Servicing & Maintenance; Vehicle Parts & Repairs; Engine Oil & Lubricants; Travel & Transport (General); Field Outreach & Ministry; Supplies & Materials; Communication & Data; Accommodation & Meals; Admin & Banking Fees; Miscellaneous / Other. |
| Itemised expenses | Every expense has itemised lines. Proposed schema representation: keep category and original currency on the parent expense; give each line a description and amount, and reconcile the expense total to its lines. Per-line categories and additional line fields are not approved. |
| Receipts | Every expense requires a receipt regardless of category or amount. No threshold or exception is approved. File size/type limits must be set before enabling uploads; do not waive the receipt requirement by inference. |
| Disbursement confirmations | Accumulate confirmed receipts against the amount sent. Partial receipts remain awaiting/partially confirmed; mark confirmed only when cumulative receipts equal the amount sent. A missionary dispute or discrepancy sets status to disputed. A settled short payment may close only with a variance/fee note and audit trail. Flag overpayment for Financial Director review/reconciliation and record it with a financial adjustment; never silently overwrite history. |
| Expenses above received funds | Do not block an expense solely because it exceeds confirmed received funds. Warn and flag the excess, and require a note. Only approved expenses count in the reimbursement calculation. |
| Carry-forward | Unused confirmed 2027 funds carry forward to the next 2027 reporting period; they are not wiped out at period end. The Financial Director reviews period close and any caps through approved financial adjustments. Do not carry funds into a pre-2027 period or invent opening balances. |
| Reimbursement | Calculate `reimbursement_due = max(0, approved_expenses - confirmed_received_net)`. Draft, submitted, queried, and rejected expenses do not count. The Financial Director reviews and settles reimbursement after approval/reconciliation. Correct or reverse records through `financial_adjustments`/reversals, never by deleting history. |
| Currency and GHS reporting | Preserve every transaction's original currency and native amount. Use the exchange rate recorded on that transaction; GHS uses 1.0. Each non-GHS transaction must record an explicit rate, rate date, and source note. Convert to GHS and round reporting, balance, and reimbursement values to two decimals (`numeric(14,2)`); never replace native amounts with converted amounts. |

## Stage 3 implementation plan

### Schema and calculations

- Create a new additive migration after the current Stage 2 migrations. Do not rewrite
  the remote-schema snapshot, alter Stage 2 grants, insert test rows, or backfill
  invented 2026/2027 transactions.
- Add `expense_lines` with an ID, `expense_id` FK, description, and positive native
  amount (`numeric(14,2)`). Keep category and currency on `expenses`. Validate, in the
  same transaction that submits the expense, that at least one line exists and the
  line sum exactly equals the parent amount. A normal row-level `CHECK` cannot enforce
  this cross-row invariant; use a constrained database function/transaction path or an
  appropriate deferred constraint trigger. Preserve draft editing until submission.
- Represent the exact approved 11 categories in `expense_categories` and set
  `receipt_required = true` for every category. Require at least one valid receipt link
  before submission. Preserve private storage; enforce approved upload limits/types
  when those limits have been decided.
- Treat `disbursement_confirmations` as an append-only receipt-event history. For each
  `confirm` event, add the received amount to the running total atomically; do not
  overwrite prior events. A dispute changes the parent to `disputed` and keeps the
  event/note. Keep the existing awaiting state while partial (the UI may label it
  “Partially confirmed”); set `confirmed` only at exact equality. Add a documented
  short-settlement path requiring variance/fee note and Financial Director review.
  Flag overpayment for Financial Director reconciliation and a linked financial
  adjustment; never silently clamp or replace the received total.
- Add an idempotency key with a unique constraint for confirmation submissions so
  retries cannot create a second receipt event. Decide key lifetime and whether one
  key is scoped to a user or disbursement before enabling writes.
- Retain `exchange_rate_to_ghs` on disbursements and expenses; add rate-date and
  source-note fields to both and add rate, date, and source-note fields to
  `financial_adjustments`. Require rate `1.0` for GHS; require a positive explicit rate,
  date, and source note for each non-GHS transaction. Do not fabricate rates to
  backfill existing records. Preserve native currency/amount and calculate GHS values
  with two-decimal rounding.
- Define one transaction-safe financial calculation path returning native amounts and
  GHS equivalents. Proposed netting to validate before coding:
  - Sum confirmed disbursement receipt events once; add approved signed adjustments
    linked to disbursements once, including explicit reversal entries.
  - Sum approved expenses; apply approved correction/reversal adjustments linked to
    expenses once. Do not count reimbursement settlement adjustments as new expenses.
  - Include carry-forward opening funds in period availability exactly once; do not
    count it again as a receipt or adjustment.
  - Calculate `reimbursement_due = max(0, approved_expenses_GHS -
    confirmed_received_net_GHS)`. Recalculate under a transaction/lock when approving
    expenses, confirming receipts, settling adjustments, or closing a period.
- Make adjustment records append-only in practice: corrections use signed adjustments,
  reversals link through `reversal_of_id`, and approval records actor/time. Define which
  adjustment types affect which side of the net formula before adding constraints.
- Carry forward unused confirmed funds between 2027+ periods through an auditable,
  Financial Director-reviewed adjustment. Do not discard unused balances; leave
  caps/period-close rules subject to the confirmations below.

### RLS, authorization, and audit

- Preserve every existing grant, including `financial.read`, `financial.manage`, and
  `financial.roles.manage`; add no financial grants to other roles. Keep existing own
  read policies. No missionary expense-submission or confirmation writes are approved.
- Enable RLS on any new table. Grant authenticated clients only the SQL operations
  needed by approved actions, and add policies scoped to active users with
  `financial.manage` for writes. For expense lines and receipts, constrain access
  through the parent expense/disbursement; retain existing own-record reads without
  implying write access. Keep table privileges and RLS aligned.
- Check active profile and exact permission in every server action and again in the
  database write path; never treat UI hiding as authorization. Preserve dashboard
  `/sign-in` redirects and inactive-profile restrictions. Avoid broad service-role
  bypasses for user-initiated finance actions.
- Make Financial Director reviews append-only rows containing reviewer, decision,
  comments, old/new status, and timestamp. Require `financial.manage`; enforce the
  approved transition matrix and prohibit self-approval if confirmed. Rejections,
  queries, re-submissions, and settlement must retain prior review records.
- Add append-only audit events for expense/line creation and changes, confirmations
  and disputes, status transitions, receipt metadata, FX values, reviews, adjustments,
  carry-forward, and reimbursement settlement. Capture actor, entity, timestamp, and
  relevant before/after status/amount/currency/rate values. Deny update/delete/truncate
  of audit history and never store receipt contents.

### `/dashboard/finance` and behavior

- Add `/dashboard/finance` as a child of the existing authenticated dashboard layout.
  Require `financial.read` for page data and independently require
  `financial.manage` for each mutation. Keep `/dashboard`, `/dashboard/users`, the
  existing Finance link behavior, and `/dashboard#finance` working; provide a deliberate
  link to the new route without removing the anchor.
- Page boundaries: list/search/filter disbursements and expenses, review queues,
  receipt metadata, native and GHS totals, period balance/carry-forward, adjustments,
  and reimbursement. Do not return private receipt contents unless the caller passes
  the same parent-record authorization checks as the receipt metadata.
- Server-action boundaries: validate IDs, amounts, currency/rate/date/source, receipt
  links, period year, and status transition; derive actor from the authenticated
  session; require notes for over-funds warnings and short settlements; submit one
  atomic database operation for line totals, confirmation totals, and net balances.
  Return explicit authorization/validation/conflict errors and do not accept actor,
  status, cumulative balance, or GHS total as trusted client input.
- Keep expense submissions idempotent through existing `client_submission_id`; add
  equivalent idempotency for receipt events. Do not enable query/reject/resubmit/cancel
  actions until the transition decisions below are approved.

## Remaining implementation decisions

Do not invent answers to these operational details; resolve them before enabling the
corresponding workflow.

| Item | Still to define |
| --- | --- |
| Receipt uploads | Maximum file size, allowed MIME/extensions, count limits per expense, and any exceptional process. No amount/category waiver is approved; determine whether a receipt can be replaced while preserving its audit history. |
| Expense transitions | For each current state (`draft`, `submitted`, `queried`, `approved`, `rejected`, `cancelled`), specify allowed next states, who can perform them, whether queried items may be edited/resubmitted, whether rejection is terminal, whether submitters can cancel, and whether self-approval is prohibited. |
| Disbursement transitions | Specify state behavior for awaiting/partial, confirmed (exact amount only), disputed, cancelled, settled-short, and overpayment-reconciliation. Decide whether partial is a stored status or derived from amount; define who clears disputes and who approves short settlement. |
| Confirmation amount and retries | Confirm that each confirmation amount represents a new incremental receipt (as proposed), rather than a cumulative snapshot. Specify idempotency key creation, scope, retention, and conflict response so a network retry cannot double-count a receipt. |
| Expense line categories | Confirm whether all lines inherit the single parent category (as proposed) or may be assigned different categories; finalize line fields and rounding/reconciliation behavior before schema creation. |
| Adjustment netting | Approve which adjustment types and signs affect disbursement receipts versus approved expenses; ensure reversals offset their referenced adjustment once. Decide whether carry-forward funds are included in `confirmed_received_net` for the reimbursement formula or tracked separately in available balance. |
| Route contents and navigation | Specify finance screen views, filters, pagination, and which actions each view exposes. Decide whether the existing Finance link changes to `/dashboard/finance` or stays at `/dashboard#finance`; both routes/anchors must remain functional. |
| Server-action boundaries | Confirm the action inventory (create/update disbursement, confirm/dispute, expense submit/revise, review, short settlement, adjustment, reimbursement, period close) and exact permission for each. Baseline plan: page reads require `financial.read`; all writes require active profile plus `financial.manage`; no new role grants or own-record writes. |
| Period handling | Whether transaction dates must fall within their reporting period, how the Financial Director approves carry-forward caps/close adjustments, and how carry-forward is represented in the next 2027+ period without counting it twice. |

## Validation and deployment plan

- Test authorized Financial Director reads/writes and denial for every other role; test
  active-profile and unauthenticated route guards.
- Test required receipts, line-total reconciliation, partial/equal/short/overpaid
  confirmations, expense-over-funds warning/note, queried/rejected workflows,
  duplicate retries, carry-forward, reimbursement formula, GHS rounding/native
  currency retention, and period boundaries with approved 2027+ scenarios only.
- Review the additive migration and live RLS policies through the approved Supabase
  deployment process before enabling finance writes. Do not insert test or historical
  financial data.

## Schema references

- `supabase/migrations/20261124235636_remote_schema.sql`
- `supabase/migrations/20261125163225_stage2_roles_user_management.sql`
- `app/dashboard/page.tsx`
- `app/dashboard/layout.tsx`
