# Stage 3 Financial Management

## Scope and current baseline

This is a policy decision sheet and implementation checklist, not an authorization to
introduce financial rules. Keep Stage 3 within the existing authenticated dashboard and
the 2027+ reporting-period scope. Do not create test data or 2026 historical records.

- The dashboard finance card and navigation item are currently the `#finance` anchor,
  shown to users with `financial.read`; there is no dedicated finance route yet.
- The dashboard layout redirects unauthenticated users to `/sign-in` and restricts
  inactive profiles. Preserve both guards.
- Stage 2 grants `financial.read` and `financial.manage` to the Financial Director.
  System Administrators, Office Staff, Missionaries, and Field Directors do not receive
  those permissions by default.
- Existing RLS allows financial-permission reads and limited own-record reads. Stage 3
  write access must be explicitly scoped in server actions and RLS.
- Existing tables include `disbursements`, `disbursement_confirmations`,
  `disbursement_receipts`, `expenses`, `expense_categories`, `expense_receipts`,
  `expense_reviews`, and `financial_adjustments`. Reporting periods constrain years to
  2027 or later.

## Decisions requiring confirmation

Record an approved decision and its owner before implementing the related behavior.

| Topic | Decision required |
| --- | --- |
| Routes and visibility | Confirm whether to add `/dashboard/finance` and which views it contains. Keep `#finance` working or redirect it deliberately; do not silently remove the existing dashboard entry. |
| Role boundaries | Confirm whether Missionaries may submit their own expenses or confirm their own disbursements. Confirm whether Office Staff or Field Directors receive any finance access. No role receives access by inference. |
| Expense categories | Approve the category list, who maintains it, and whether inactive categories remain visible on historical 2027+ expenses. |
| Receipts | Define category requirements, any amount threshold, permitted exceptions, file limits/types, and who may view uploaded receipts. Existing `receipt_required` is a category-level boolean; no threshold is defined. |
| Partial receipt | Define whether confirmation amounts are incremental or cumulative, how totals update, and when a disbursement is considered confirmed, disputed, or still awaiting confirmation. |
| Available funds and overspend | Define the balance formula, the treatment of multiple disbursements/currencies/exchange rates, whether expenses above received funds are blocked or allowed, and who may override. |
| Expense review | Define whether queried expenses may be edited/resubmitted, whether rejection is terminal, whether submitters can cancel, and whether a reviewer may approve their own submission. Preserve review history. |
| Carry-forward and period close | Define whether unused funds carry to another period and how/when a period is closed. Do not infer this from `reporting_period_id`. |
| Reimbursements and adjustments | Define whether/how reimbursements are paid and recorded, who requests and approves them, and how corrections/reversals work. The existing adjustment table does not settle these policies. |
| Currencies and dates | Confirm allowed currencies, when exchange rates are mandatory, the conversion convention, and whether expense/disbursement dates must fall within their reporting period. |

## Role boundary baseline

| Role | Current financial access | Stage 3 boundary |
| --- | --- | --- |
| Financial Director | `financial.read`, `financial.manage` | Finance screens and management actions may be permission-gated here, subject to approved separation-of-duties rules. |
| System Administrator | No financial permissions by default | Keep user administration separate from confidential finance access. |
| Office Staff | No financial permissions by default | No finance access unless a specific policy and permission are approved. |
| Missionary | Limited own-record reads under existing RLS; no finance write permission | Any own expense submission or receipt confirmation requires an approved, narrowly scoped permission and matching RLS. |
| Field Director | No financial permissions by default | Do not grant access based on field oversight alone. |

## Implementation checklist

- [ ] Resolve the decision table above; leave unapproved rules unimplemented.
- [ ] Design the route/navigation only after visibility decisions; preserve `/dashboard`,
  `/dashboard/users`, sign-in behavior, active-profile guards, and existing permissions.
- [ ] Add server actions with authorization checks on every operation, input validation,
  explicit status transitions, ownership checks where approved, and clear error results.
- [ ] Make balance-sensitive updates atomic. Preserve `client_submission_id`
  idempotency for expense submissions; define idempotency for receipt confirmations.
- [ ] Add narrowly scoped RLS policies for each approved read/write path. Do not rely on
  UI filtering as authorization; retain existing own-record protections.
- [ ] Add append-only audit coverage for financial creation, edits, decisions, receipts,
  and adjustments, recording actor and status/amount changes without storing file contents.
- [ ] Keep changes in additive Stage 3 migrations; avoid test inserts, 2026 historical
  records, and unrelated route/auth/role changes.
- [ ] Test Financial Director access and denials for every other role, plus partial
  receipts, over-balance expenses, queried/rejected/resubmitted expenses, duplicate
  submissions, receipt access, and period boundaries using approved 2027+ scenarios.
- [ ] Review and apply the Stage 3 migration through the approved Supabase deployment
  process; verify the live RLS policies before enabling finance writes.

## Schema references

- `supabase/migrations/20261124235636_remote_schema.sql`
- `supabase/migrations/20261125163225_stage2_roles_user_management.sql`
- `app/dashboard/page.tsx`
- `app/dashboard/layout.tsx`
