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

- Add an additive Stage 3 migration; do not modify the baseline or Stage 2 migrations.
- Add an expense-line table linked to `expenses`, with line description and native
  amount. Preserve the existing expense-level category and currency. Enforce that
  submitted line totals reconcile to the parent amount in a transaction-safe path.
- Represent the approved category list in `expense_categories`, with
  `receipt_required = true` for all 11. Do not add unapproved categories or test rows.
- Require receipt links before expense submission. Keep file storage private and
  validate upload limits/types once those operational limits are set.
- Store confirmation entries as auditable receipt events and derive the cumulative
  amount atomically. Keep partial receipts awaiting confirmation (or display a derived
  partial state); confirm only at exact equality. Support documented short settlement
  and overpayment reconciliation without rewriting receipt history. Define retry
  idempotency before enabling confirmation writes.
- Add rate date and source-note fields wherever a transaction can have a non-GHS
  currency, including adjustments. Enforce GHS rate `1.0` and require explicit positive
  rate/date/source for non-GHS transactions. Retain the native amount/currency.
- Add transaction-safe GHS calculations rounded to two decimal places. Implement
  `reimbursement_due` from approved expenses and confirmed received net; document and
  test which approved adjustments/reversals contribute to the `net` amount to prevent
  double counting. Make balance-sensitive updates atomic.
- Support period carry-forward only between 2027+ reporting periods, with Financial
  Director review and auditable adjustments. Define any cap/close mechanics without
  discarding unused confirmed funds.

### RLS, authorization, and audit

- Keep all existing financial grants unchanged, including `financial.read`,
  `financial.manage`, and `financial.roles.manage`. Do not grant finance permissions
  to other roles or add missionary finance writes without separate approval.
- Keep financial reads behind existing permission/own-record policies. Add narrowly
  scoped RLS policies for each Stage 3 write path; do not rely on UI filtering.
- Check active-profile and permission requirements in every server action as well as
  RLS. Restrict management writes and review/settlement decisions to
  `financial.manage`; retain the existing sign-in and inactive-profile guards.
- Authorize receipt metadata and private file access through the related financial
  record and approved permission/ownership rules. Never expose file contents through
  audit records.
- Extend append-only audit coverage to financial creation/edit, line changes,
  confirmation/dispute/settlement, receipt metadata, expense review, currency-rate
  changes, carry-forward, reimbursement, and adjustments. Record actor, entity,
  timestamp, and relevant before/after status and amounts; prohibit mutation/deletion
  of audit history.

### `/dashboard/finance` and behavior

- Add `/dashboard/finance` within the existing authenticated dashboard layout. Require
  `financial.read` to view and `financial.manage` for management actions.
- Keep `/dashboard`, `/dashboard/users`, and the existing `/dashboard#finance` anchor
  working. Add a deliberate path from the existing finance entry to the new screen
  without silently removing the anchor or changing unrelated routes.
- Include views for disbursements/confirmations, expense lines and receipts, review
  queues, balances/carry-forward, reimbursements/adjustments, and GHS reports while
  retaining original currency values.
- Show warnings and require a note when an expense exceeds confirmed received funds;
  do not block solely for that reason. Surface disputes, short-settlement variance,
  and overpayment reconciliation to the Financial Director.
- Preserve `client_submission_id` idempotency for expense submissions and define
  explicit status transitions and retry protection for confirmation events.

## Remaining implementation decisions

Do not invent answers to these operational details; resolve them before enabling the
corresponding workflow.

| Item | Still to define |
| --- | --- |
| Route contents | Exact screens, filters, and whether the existing finance navigation link points to the new route or remains the dashboard anchor. Both locations must continue to work. |
| Expense review | Whether queried expenses can be edited/resubmitted, whether rejection is terminal, whether submitters can cancel, and whether self-approval is prohibited. |
| Expense line categories | Whether all lines inherit one parent category or can be assigned different categories; confirm before finalizing the line schema. |
| Receipt uploads | File size/type limits and any exceptional handling. No amount-based or category-based waiver is approved. |
| Confirmation retries | How a client identifies a retry versus a new receipt event; keep event history and prevent duplicate amounts. |
| Short settlement | The explicit close status/transition and Financial Director approval required for a settled short payment. |
| GHS net formula | Which approved financial adjustments/reversals affect `confirmed_received_net`, avoiding double counting. |
| Period handling | Whether transaction dates must fall within their reporting period, and how the Financial Director approves any carry-forward cap/period-close adjustment. |

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
