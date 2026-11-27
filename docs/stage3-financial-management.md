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
| Itemised expenses | Every expense has itemised lines with per-line category. The parent total/summary is derived from the lines; never overwrite it with an independent client value or invent item data. |
| Receipts | Every expense requires receipts, with no amount/category waiver: max 5 MB per file, JPEG/PNG/WebP/PDF only, and max 5 active receipts per expense. Replacement is allowed only while draft or queried; preserve superseded receipt and audit history. |
| Disbursement confirmations | Every confirmation event is tagged incremental or cumulative and totals are calculated deterministically. Partial receipts use `partially_confirmed`; `confirmed` requires exact equality with amount sent. Missionary disputes set `disputed`; only the Financial Director resolves them. A settled short payment uses `settled_short` with variance/fee note and Financial Director approval. Overpayment requires Financial Director reconciliation and a linked `financial_adjustments` entry; never silently overwrite history. |
| Expenses above received funds | Do not block an expense solely because it exceeds confirmed received funds. Warn and flag the excess, and require a note. Only approved expenses count in the reimbursement calculation. |
| Carry-forward | Unused confirmed 2027 funds carry forward to the next 2027 reporting period; they are not wiped out at period end. The Financial Director reviews period close and any caps through approved financial adjustments. Do not carry funds into a pre-2027 period or invent opening balances. |
| Reimbursement | Calculate `reimbursement_due = max(0, approved_expenses - confirmed_received_net)`. Draft, submitted, queried, rejected, and cancelled expenses do not count. Carry-forward contributes to `available_balance`, not `confirmed_received_net`. The Financial Director reviews/settles reimbursement; correct or reverse through adjustments, never delete history. |
| Currency and GHS reporting | Preserve every transaction's original currency and native amount. Use the exchange rate recorded on that transaction; GHS uses 1.0. Each non-GHS transaction must record an explicit rate, rate date, and source note. Convert to GHS and round reporting, balance, and reimbursement values to two decimals (`numeric(14,2)`); never replace native amounts with converted amounts. |

## Stage 3 implementation plan

### Schema and calculations

- Create a new additive migration after the current Stage 2 migrations. Do not rewrite
  the remote-schema snapshot, remove existing data, alter existing permission grants,
  insert test rows, or import/backfill invented historical transactions. Every
  transaction and reporting period handled by Stage 3 must be 2027 or later.
- Add `expense_lines` with `id`, `expense_id`, `expense_category_id`, description,
  positive native `amount numeric(14,2)`, and timestamps. The category belongs to each
  line. For new itemised expenses, make the old parent `expense_category_id` a
  compatibility/summary field, nullable where line categories differ; never invent a
  category or line to fill old data. Keep parent currency. A trusted database write
  path recalculates the header amount from its lines in the same transaction; clients
  cannot supply an independent header total. Require at least one line and exact
  line/header equality at submission. Use a transaction/deferred constraint trigger,
  not a row-level `CHECK`, for this cross-row invariant. Leave pre-existing records
  intact; only itemise them from verified source records.
- Keep the 11 approved categories in `expense_categories`, with
  `receipt_required = true`. Validate receipt content type and extension against JPEG
  (`image/jpeg`, `.jpg`/`.jpeg`), PNG (`image/png`, `.png`), WebP (`image/webp`,
  `.webp`), or PDF (`application/pdf`, `.pdf`); enforce `size_bytes <= 5,000,000` and
  no more than 5 active receipts per expense. Validate server-side, including file
  signature, not only the browser MIME value. Add a nullable self-reference such as
  `supersedes_receipt_id` to receipt links; permit replacement only while draft or
  queried. Lock the parent expense while counting active receipt links so concurrent
  uploads cannot exceed 5. Keep superseded links and audit history; never silently
  delete replaced receipts. Apply these upload limits only to financial receipt
  actions; do not constrain the shared `file_assets` limit for unrelated modules.
- Treat `disbursement_confirmations` as append-only receipt events with required
  `amount_mode` (`incremental` or `cumulative`). Store every event and its idempotency
  key. In one locked transaction, order events by server-assigned sequence: an
  incremental event adds its amount to the running total; a cumulative event replaces
  it with the reported total, and may not reduce the prior total (correction requires
  an approved adjustment). Keep the event mode explicit. Keep
  `awaiting_confirmation` when there is no receipt, use `partially_confirmed` when the
  effective amount is positive but below `amount_sent`, and use `confirmed` only at
  exact equality. A missionary dispute sets `disputed`; only the Financial Director
  may clear it, with resolution notes and audit. A settled short payment uses
  `settled_short` and requires Financial Director approval plus a variance/fee note.
  Overpayment is flagged with `reconciliation_required` for Financial Director
  reconciliation through a linked approved adjustment; never clamp or overwrite
  confirmation history.
- Replace the disbursement status `CHECK` in the new migration (without deleting
  records) to admit `partially_confirmed` and `settled_short` alongside
  `awaiting_confirmation`, `confirmed`, `disputed`, `cancelled`, and
  `reconciliation_required`. Add checked fields or an append-only resolution event for
  Financial Director actor/time/note on dispute resolution and short settlement;
  clear reconciliation only with the approved linked adjustment and deterministic
  recalculation.
- Store confirmation idempotency persistently, scoped to authenticated user and
  operation. Add a persistent client key and canonical request hash; enforce unique
  `(confirmed_by, decision, client_submission_id)`. Same key plus same payload returns
  the original committed result; same key with changed payload returns a conflict.
  Retain the key across offline retries and reconciliation. Preserve existing
  `client_submission_id` idempotency for expense submission.
- Retain `exchange_rate_to_ghs` on disbursements and expenses. Add exchange-rate date
  and source-note fields to both, and rate/date/source fields to financial adjustments.
  Require rate `1.0` for GHS. For non-GHS records require a positive rate, rate date,
  and non-empty source note. Keep the original currency/native amount immutable after
  approval; do not fabricate/backfill rates. Preserve existing rows with no made-up
  rate; require the FX fields on every new Stage 3 write and validate existing records
  only after genuine source data is available. Convert using the recorded transaction
  rate and round GHS report/balance/reimbursement values to `numeric(14,2)`.
- Validate every transaction date against the selected reporting period's inclusive
  `start_date`/`end_date` and enforce period year >= 2027 in the trusted write path.
- Implement atomic balance/reimbursement calculations in a database function or
  equivalent transaction-safe path. Only approved adjustments affect totals:
  disbursement-linked signed adjustments affect `confirmed_received_net`; expense-
  linked signed adjustments affect `approved_expenses`; exclude all non-approved
  expenses and do not count reimbursement settlements as new expenses. A reversal
  must reference one target, equal its exact negative amount, retain its currency/rate,
  and not itself be reversed. Enforce at most one reversal with a partial unique index
  on `reversal_of_id` plus a trigger/function that rejects reversal chains. Count
  carry-forward once in `available_balance`, but exclude it from
  `reimbursement_due = max(0, approved_expenses - confirmed_received_net)`. Compute
  totals in GHS with two-decimal rounding and lock/recheck when approval, confirmation,
  adjustment, or period-close writes can change the result.
- Add `carry_forward` to the adjustment type constraint and represent an unused
  confirmed balance as one Financial Director-reviewed, audited adjustment into the
  next 2027+ period. Do not delete or wipe balances; include the adjustment in
  `available_balance` only, not as new confirmed receipts or reimbursement net.

### RLS, authorization, and audit

- Preserve existing grants (`financial.read`, `financial.manage`, and
  `financial.roles.manage`) and add no broader grants. Add only these scoped
  capabilities to existing roles by additive `permissions` and `role_permissions`
  rows; never replace the existing grants:
  - Missionary: manage own expenses only while draft/queried; submit/cancel own
    unapproved expenses; confirm or dispute disbursements linked to own missionary
    record. Suggested permission codes: `financial.expenses.own_manage` and
    `financial.disbursements.own_confirm`.
  - Office Staff: create disbursements and attach payment evidence for those
    disbursements; no approval, dispute resolution, or general finance read. Suggested
    codes: `financial.disbursements.create` and
    `financial.disbursements.evidence`.
  - Financial Director: retain existing `financial.read`/`financial.manage`; only this
    role (through `financial.manage`) approves/queries/rejects expenses, resolves
    disputes, approves settled-short outcomes, and approves/reverses adjustments.
- Seed the four proposed capabilities only to the existing `missionary` and
  `office_staff` roles as listed above. Do not grant either role `financial.read`,
  `financial.manage`, or `financial.roles.manage`. Keep role/user IDs and all current
  assignments unchanged.
- Enable RLS on `expense_lines` and any added tables. Keep full finance reads behind
  `financial.read`; allow explicitly scoped owner reads/writes only through the new
  Missionary capabilities and parent ownership checks. Allow Office Staff to read
  their created disbursements and manage evidence only on those records. Require
  `financial.manage` for Financial Director decisions. Grant only the SQL operations
  each path requires, and align table privileges with RLS.
- Add database-side authorization helpers/policies for the exact capability strings
  and active-user check. Any `SECURITY DEFINER` transaction function must pin
  `search_path`, derive the actor from `auth.uid()`, recheck the required permission
  and ownership, and expose only the intended operation.
- Check authenticated session, active profile, capability, record ownership, and
  workflow state in every server action and again in the database write path. Derive
  actor from `auth.uid()`/server session; never accept caller-supplied actor or
  permission. Preserve `/sign-in` and inactive-profile guards. Do not use a broad
  service-role bypass for user-initiated writes.
- Enforce Financial Director approval paths in both action and database layer. Reviewer
  must differ from expense submitter/creator; preserve review rows with reviewer,
  decision, comments, previous/new status, and timestamp. Each transition writes its
  own review/audit record; corrections to approved expenses use adjustments, not edits.
- Keep the dashboard Finance navigation entry visible to users with `financial.read`
  and add limited own/created-record entry points for the new scoped capabilities.
  Do not grant those users the full finance menu or expose cross-missionary results.
- Add append-only audit coverage for expense and line changes, receipt creation and
  replacement, confirmations/mode/disputes/resolutions, status transitions, FX values,
  reviews, adjustments/reversals, carry-forward, and reimbursement settlement. Record
  actor, entity, timestamp, and before/after status, amount, currency, and rate as
  appropriate. Deny audit update/delete/truncate; never record receipt file contents.

### `/dashboard/finance` and behavior

- Make `/dashboard/finance` the primary Finance destination and retain `/dashboard#finance`
  as a working anchor/compatibility entry. Do not alter `/dashboard`, `/dashboard/users`,
  the dashboard sign-in redirect, or inactive-profile guard. Full finance views require
  `financial.read`; role-scoped Missionary/Office Staff pages/actions expose only their
  allowed own/created records and actions.
- Views: Summary & Balances (available balance, carry-forward, reimbursement due,
  native and GHS totals); Disbursements & Confirmations; Expenses & Line Items with a
  Financial Director review queue; and Adjustments/Reversals (only for authorized
  users). Display original currency/amount beside converted GHS. Surface excess-funds
  warnings, disputes, settled-short variance, and overpayment reconciliation to the
  Financial Director.
- Filters: reporting period (2027+), status, line category, currency, date range, and
  missionary only for roles allowed to see cross-missionary records. Use server-backed
  pagination with 25 records per page by default and bounded page size.
- Server actions: list/read checks session + active profile + `financial.read`, or the
  precise scoped own/created-record capability. Missionary actions are limited to own
  draft/queried expense edits, submission/cancellation, and own disbursement
  confirmation/dispute. Office Staff can create disbursements and add their payment
  evidence. Every mutation checks active profile, exact scoped capability or
  `financial.manage`, ownership, reporting-period dates/year, input bounds, and the
  allowed transition. Financial Director-only actions are review decisions, dispute
  resolution, settled-short approval, and adjustment approval/reversal.
- Derive actor from the session; do not trust client status, owner, total, FX-converted
  amount, or reviewer fields. Use one atomic database operation for line/header totals,
  receipt totals, adjustment netting, and balance checks. Require the approved note on
  over-funds warnings and settled-short outcomes. Return explicit validation,
  authorization, and idempotency-conflict errors.
- Reuse `client_submission_id` for expenses. For confirmation events persist a key
  scoped to user and operation with the canonical request hash: same key/hash returns
  the original result, changed payload returns a conflict. Retain keys for offline
  retry; never duplicate event, attachment, or audit rows on a retry.

## Confirmed workflow boundaries

| Actor | Allowed Stage 3 actions | Enforcement |
| --- | --- | --- |
| Missionary | Create/edit own draft or queried expenses with categorized lines and receipts; submit or cancel own unapproved expenses; confirm or dispute own linked disbursements. | Scoped capabilities only; parent missionary ownership; no approve/reject/adjustment authority. |
| Office Staff | Create disbursements and attach payment evidence to records they created. | Scoped capabilities only; no general finance read, review, dispute-resolution, or adjustment authority. |
| Financial Director | Read finance records; approve/query/reject expenses; resolve disputes; approve `settled_short`; approve/reverse adjustments and carry-forward/period-close actions. | Existing `financial.read` / `financial.manage`; no self-approval; all decisions audited. |

Preserve existing grants and role identities. The confirmed new Missionary and Office
Staff capabilities are additive, narrowly scoped grants, not additions of
`financial.read` or general `financial.manage`. Proposed permission identifiers in
this plan are `financial.expenses.own_manage`, `financial.disbursements.own_confirm`,
`financial.disbursements.create`, and `financial.disbursements.evidence`.

## Final implementation guards

- Expense transition matrix: `draft -> submitted|cancelled`;
  `submitted -> queried|approved|rejected|cancelled`;
  `queried -> submitted|cancelled`; `approved`, `rejected`, and `cancelled` are
  terminal. Missionary/submitter may cancel only before approval; Financial Director
  makes review decisions. Queried edits/resubmissions retain notes, receipts, and
  history. Creator/submitter cannot approve their own expense. Corrections to approved
  expenses use adjustments.
- Disbursement transition matrix: `awaiting_confirmation ->
  partially_confirmed|confirmed|disputed|reconciliation_required|cancelled`;
  `partially_confirmed ->
  partially_confirmed|confirmed|disputed|settled_short|reconciliation_required`;
  `confirmed -> disputed|reconciliation_required` on a missionary discrepancy or
  later overpayment event;
  `disputed -> partially_confirmed|confirmed|settled_short` only after Financial
  Director resolution; `reconciliation_required -> confirmed` only after an approved
  linked adjustment reconciles the effective amount. `settled_short` and `cancelled`
  are terminal. Confirmation is incremental or cumulative per event as tagged; exact
  equality is required for `confirmed`. Underpayment may settle short only with a
  variance/fee note and Financial Director approval. Any overpayment goes to
  `reconciliation_required`, with an approved adjustment before it can return to
  `confirmed`.
- Confirmation/offline retry keys are persistent and scoped per user and operation.
  Same key and canonical payload returns the original result; changed payload conflicts.
  Do not duplicate confirmation, receipt, or audit rows on retry.
- All date-window and financial write checks apply only to 2027+ reporting periods.
  Do not import 2026 historical transactions, fabricate FX rates, or invent line items.
- These are specification decisions only. Before enabling workflows, review the
  additive migration, grant assignment, RLS policies, server actions, and live Supabase
  policy state. No destructive migration or application-code change is authorized by
  this document update.

## Validation and deployment plan

- Test Financial Director access and denials; test Missionary ownership restrictions
  and allowed own-record actions; test Office Staff create/evidence scope and denials
  for review/finance-wide access. Test active-profile and unauthenticated route guards.
- Test file size/type/count enforcement and receipt replacement/history; line-category
  totals; all expense/disbursement transitions; incremental and cumulative events;
  exact equality/short/overpaid handling; one-time reversal guard; offline retries with
  identical and changed payloads; carry-forward exclusion from reimbursement; FX
  rounding/native currency retention; and period-date/year validation using 2027+
  scenarios only.
- Review the additive migration and live RLS policies through the approved Supabase
  deployment process before enabling finance writes. Do not insert test or historical
  financial data.

## Schema references

- `supabase/migrations/20261124235636_remote_schema.sql`
- `supabase/migrations/20261125163225_stage2_roles_user_management.sql`
- `app/dashboard/page.tsx`
- `app/dashboard/layout.tsx`
