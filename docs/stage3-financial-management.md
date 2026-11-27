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

| Item | Current schema status | Question to confirm |
| --- | --- | --- |
| Routes and visibility | Finance is the `#finance` dashboard anchor, visible with `financial.read`; no dedicated finance route exists. | Add `/dashboard/finance`, and which views should it contain? Keep `#finance` working or redirect it deliberately? Preserve the sign-in and active-profile guards. |
| Role boundaries | Stage 2 grants the Financial Director `financial.read` and `financial.manage`; other roles receive no finance permissions by default. Own-record reads exist for some records, but there are no finance write policies. | May Missionaries submit expenses or confirm their own disbursements? Should Office Staff or Field Directors receive any finance access? Do not infer new access. |
| Expense categories | Categories have `code`, `name`, `is_active`, and a category-level `receipt_required` flag. | What categories are approved, who maintains them, and should inactive categories remain visible on historical 2027+ expenses? |
| Itemised expenses | An expense stores one category, amount, and description; there is no expense line-item table. | Are expenses itemised? If so, what fields and category rules apply per line? |
| Receipts | Disbursement and expense receipt links to private file assets exist. There is no receipt threshold or exception policy. | Which categories require receipts, are there amount thresholds or exceptions, what file limits/types apply, and who may view uploaded files? |
| Disbursement receipt confirmation | Disbursements store status and received amount/date; confirmation rows support `confirm` or `dispute`, amount, date, and notes. | Are partial amounts incremental or cumulative? How do they update totals, and when is a disbursement confirmed, disputed, or awaiting confirmation? What prevents duplicate confirmations? |
| Financial Director expense review | Expense statuses include `submitted`, `queried`, `approved`, and `rejected`; review rows record decisions and status changes. No transition rules are enforced by the schema. | Which transitions are allowed? Can queried expenses be edited/resubmitted, is rejection terminal, can submitters cancel, and may a reviewer approve their own submission? Preserve review history. |
| Available balance and overspend | No balance formula or financial aggregation exists. Disbursement, expense, and adjustment amounts/currencies are stored separately. | How is available balance calculated, which records count, and how are multiple disbursements, currencies, and exchange rates treated? Are over-balance expenses blocked or allowed, and who may override? |
| Reimbursements and adjustments | Adjustments support pending/approved/rejected states and reimbursement, correction, reversal, or other types; no payment/settlement workflow is defined. | How are reimbursements requested, approved, paid, and recorded? Who may act, and how are corrections and reversals handled? |
| Carry-forward and period close | Transactions reference a reporting period, but there is no close or carry-forward policy. | Do unused funds carry to another period? How and when is a period closed? Do not infer either behavior from `reporting_period_id`. |
| Currencies, GHS reporting, and dates | Disbursements and expenses retain currency and have optional `exchange_rate_to_ghs`; adjustments retain currency but have no rate. Generated reports are generic records, not financial summaries. Reporting periods constrain years to 2027–2100, but transaction dates are not constrained to period dates. | Which currencies are allowed, when is a rate mandatory, and what conversion/rounding convention applies? Should reports show GHS totals while retaining each original currency and amount? Must transaction dates fall within their reporting period? |
| Financial audit coverage | An append-only audit log exists, but the schema migrations do not add financial-table audit triggers. | Which financial creations, edits, decisions, receipts, and adjustments must be audited, and which actor/status/amount fields should be recorded? Never store file contents in the audit log. |

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
