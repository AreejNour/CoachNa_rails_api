# M37 — Admin panel: coach money overview (income / commission / owed) — Design

> Status: self-approved (user is AFK and authorized autonomous execution of M37: "make plan for m37 and implement it, I'm away from keyboard"). Date: 2026-11-25. Milestone: M37 (fifth admin milestone, follows M36). Mirrors the M33/M35/M36 AFK self-approval pattern.

## Intent and why

CoachNa takes a commission on every paid subscription (the percentage and amount are snapshotted onto `subscriptions.commission_percent`/`commission_piastres` at purchase, M6). The coach app already shows each coach **their own** earnings (M24). What the CoachNa team has **no view of** is the business-wide money picture: how much CoachNa has earned in commission overall, and how much it **owes each coach** (their net share, paid out manually in v1). Roadmap M37: "Income per coach … CoachNa commission totals, and what is owed to each partner. **Done when:** CoachNa can tell at any time how much it earned and how much it owes each partner." M37 adds a **read-only money overview** to the Rails admin panel: a totals banner (CoachNa-wide) plus a per-coach breakdown table.

## Goals

- A signed-in admin sees a **CoachNa-wide totals banner**: total gross income (sum of all paid subscription payments), total **CoachNa commission** (what CoachNa earned), and total **owed to coaches** (net = gross − commission).
- Below it, a **per-coach table**, highest income first: coach name, income (gross), CoachNa commission, owed to the coach (net), and the number of paid subscriptions — one row per coach that has at least one paid subscription payment.
- The money math **mirrors M24 (`CoachApp::Earnings`/`EarningsJson`) exactly** — same source rows (`payments` where `purpose = 'subscription'` AND `status = 'paid'`, joined to `subscriptions`), same per-payment definition (gross = `payments.amount_piastres`, commission = `subscriptions.commission_piastres`, net = gross − commission) — so the admin total for a coach equals that coach's own M24 summary. No new money formula.
- Money is shown in EGP (piastres ÷ 100), reusing the M36 `number_to_currency(… , unit: "EGP ", precision: 2)` convention.
- The full test suite stays green; the Node API, coach app, and client app are unchanged.

## Non-goals (this milestone)

- **Recording or performing payouts.** Payouts are manual in v1 (roadmap §5); M37 only *reports* what is owed. No payout table, no "mark paid" action, no mutation of any kind.
- **A per-coach money drill-down page** (that coach's individual paid payments). The per-coach table row answers "how much do we owe each coach"; a drill-down is deferred (keeps the milestone single-purpose — [[small-milestones]]). The coach's own M24 earnings view already itemizes their payments.
- **Restaurant income / owed** — deferred to Part 3 (restaurants don't exist yet).
- **Date-range / period filtering** (e.g. "this month"). v1 shows all-time totals; add periods later if asked (YAGNI).
- **Refund handling beyond M24 parity.** M24 counts only `paid` payments and ignores `refunded`; M37 does the same. Representing refunds as negatives is out of scope (no Node behavior for it today).

## Anti-goals (would make this a failure even if it "works")

- **A total that drifts from M24.** If the admin per-coach income/commission/net does not equal that coach's `CoachApp::Earnings.summary`, the coach app and admin disagree about money — the worst outcome. The admin aggregate must select the same rows and apply the same per-payment arithmetic.
- **Counting the wrong payments** — including `pending`/`failed`/`refunded` payments, or `order` payments (meal orders), in the money totals. Only `purpose = 'subscription'` AND `status = 'paid'`.
- **Writing to any table.** M37 is strictly read-only: no `INSERT`/`UPDATE`/`DELETE`, no schema change, no migration, no new table, no Node change.
- **Leaking the money overview** to anyone not signed in as an admin — behind `require_admin` (the `Admin::BaseController`), like every admin page.
- **An N+1 or a full-table scan per coach.** The breakdown is produced by **one grouped aggregate query**, not a query per coach.

## Constraints

- **English-only** admin UI (as M33–M36). No coach/client-facing copy (M37 sends no notifications).
- **Shared Postgres; everything M37 reads already exists and is Node-owned:**
  - `payments` — `amount_piastres int`, `purpose text` (`subscription`/`order`), `status text` (`pending`/`paid`/`failed`/`refunded`), `subscription_id uuid`, `paid_at`.
  - `subscriptions` — `coach_id uuid`, `commission_piastres int`, `commission_percent numeric(5,2)`.
  - `coaches` — `full_name`.
- **Money math is M24's, not a new one.** Authoritative definition in `app/services/coach_app/earnings.rb` + `earnings_json.rb`: rows = `Payment.where(purpose: "subscription", status: "paid").joins(:subscription)`; per payment gross = `amount_piastres`, commission = the subscription's `commission_piastres`, net = gross − commission. A subscription with N paid payments contributes its commission N times (M24 maps per payment — M37 matches by summing over the same payment rows).
- **No schema change, no migration, no new table, no Node change.**
- Reuse the M33 admin stack: `Admin::BaseController` (session auth, `current_admin` → `AdminUser`, CSRF, `admin` layout), models `Payment`/`Subscription`/`Coach`, and the `admin` route scope. Admin panel ships **no JavaScript** (a static page; no forms needed).
- **Branch `feat/m37-money-overview` off `main`** (M37 depends only on M33's admin auth, now on main along with M34–M36). Local commits only — no push, no merge (the user reviews/merges). The M34 `Gemfile.lock` downgrade already on `main` is left as-is; M37 commits never touch `Gemfile.lock` (the local downgrade stays unstaged, discard with `git checkout Gemfile.lock`).

## Approaches considered

How to produce the per-coach rollup without drifting from M24's money formula:

- **A — A dedicated `Admin::MoneyOverview` service with one grouped aggregate (CHOSEN).** A Rails service runs a single `GROUP BY subscriptions.coach_id` aggregate over the same `paid`/`subscription` payment rows M24 uses, returning per-coach `{gross, commission, net, count}` plus CoachNa-wide totals; a thin `Admin::MoneyController#index` renders it. Fast (one query), self-contained, and its result is pinned to M24 by a test that compares one coach's row to `CoachApp::Earnings.summary`. Cost: the SQL restates M24's row selection in aggregate form — contained by that equality test.
- **B — Reuse `CoachApp::Earnings.summary(coach)` per coach in a loop.** Zero formula duplication (literally calls M24), but it's one query per coach (N+1 across the coach list) and loads every payment into Ruby only to re-sum it. Rejected on performance; the aggregate in A is pinned to M24 by test instead.
- **C — A Node money endpoint the Rails UI calls.** Adds runtime Rails→Node coupling for data Rails already reads from the shared DB; breaks the self-contained-Rails-admin model (same reason rejected in M35/M36). Rejected.

**Chosen: A**, decided 2026-11-25. One sensible shape (a read-only rollup mirroring M24's numbers and M36's admin UI), so the alternatives are recorded to show why no per-coach-loop or Node layer was used.

## The design (decided)

### Service — `Admin::MoneyOverview`
`Admin::MoneyOverview.call` returns a struct/hash:
```
{
  totals: { gross_piastres:, commission_piastres:, net_piastres:, coach_count:, subscription_count: },
  coaches: [ { coach_id:, coach_name:, gross_piastres:, commission_piastres:, net_piastres:, subscription_count: }, … ]  # income desc
}
```
One aggregate query over the M24 row set:
```ruby
Payment.where(purpose: "subscription", status: "paid")
       .joins(subscription: :coach)
       .group("coaches.id", "coaches.full_name")
       .pluck(Arel.sql("coaches.id"), Arel.sql("coaches.full_name"),
              Arel.sql("SUM(payments.amount_piastres)"),
              Arel.sql("SUM(subscriptions.commission_piastres)"),
              Arel.sql("COUNT(*)"))
```
Map each row to a coach entry with `net = gross - commission`; sort by `gross` desc. `totals` = sums across the entries (`coach_count` = number of entries, `subscription_count` = sum of counts). Empty result → all-zero totals and an empty `coaches` list.

### Controller + route
`Admin::MoneyController#index` → `@overview = Admin::MoneyOverview.call`. Route inside the existing `scope path: "admin", module: "admin", as: "admin"`: `get "money", to: "money#index", as: :money` → helper `admin_money_path`.

### View — `app/views/admin/money/index.html.erb`
A totals banner (three figures: Gross income, CoachNa commission, Owed to coaches — all EGP) with the paid-subscription count; then the per-coach table (Coach, Income, CoachNa commission, Owed, Paid subs) or an empty-state line ("No paid subscriptions yet."). Money via `number_to_currency(piastres / 100.0, unit: "EGP ", precision: 2)`.

### Admin nav
Add a **Money** link (`admin_money_path`) to the admin layout nav, after Subscriptions (nav becomes Coaches | Reviews | Subscriptions | Money).

## What's left to the builder

- Whether `Admin::MoneyOverview.call` returns a `Struct`/`Data`/`OpenStruct`/plain hash — pick what reads cleanly and is easy to assert in tests; the view only needs `totals.*` and `coaches.each`.
- Exact ERB markup/column order, consistent with `app/views/admin/subscriptions/index.html.erb` and the existing admin tables.
- The precise `pluck`/`group` form (the SQL above is a guide; an equivalent `select`+aggregate is fine) as long as it is one query and selects exactly the M24 rows.
- Test seeding: reuse the M36/earnings test shape (`Coach`, `Client`, `CoachPackage`, `Subscription`, `Payment`); include the **M24-parity test** (one coach's overview row equals `CoachApp::Earnings.summary(coach)[:summary]` gross/commission/net) and the **exclusion test** (a `pending`/`failed`/`refunded` payment and an `order` payment do not move the totals).
