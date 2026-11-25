# M37 — Admin coach money overview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed-in admin can see, in the Rails admin panel, CoachNa's business-wide money picture — total gross income, total CoachNa commission earned, and total owed to coaches — plus a per-coach breakdown, all read-only and matching the coach app's own M24 earnings numbers.

**Architecture:** An `Admin::MoneyOverview` service runs ONE grouped aggregate over the exact payment rows M24 uses (`paid` `subscription` payments joined to subscriptions/coaches), returning per-coach `{gross, commission, net, count}` + CoachNa-wide totals; a thin `Admin::MoneyController#index` renders a totals banner + per-coach table. No service-to-service calls, no Node code, no schema change, no mutation.

**Tech Stack:** Rails 8 (minitest), ERB views, shared Postgres, M33 admin session stack (`Admin::BaseController`, `AdminUser`, CSRF, `admin` layout).

**Spec:** `docs/superpowers/specs/2026-11-25-m37-money-overview-design.md`

## Global Constraints

- **English-only** admin UI. No coach/client notifications (M37 sends none).
- **Read-only. No schema change, no migration, no new table, no Node change, no mutation.** M37 only reads `payments`, `subscriptions`, `coaches`.
- **Money math mirrors M24 exactly** (`app/services/coach_app/earnings.rb` + `earnings_json.rb`): rows = `Payment.where(purpose: "subscription", status: "paid")` joined to `subscriptions`; per payment gross = `payments.amount_piastres`, commission = `subscriptions.commission_piastres`, net = gross − commission. A subscription with N paid payments contributes its commission N times (sum over the same payment rows).
- Money rendered with `number_to_currency(piastres / 100.0, unit: "EGP ", precision: 2)` (the M36 convention).
- Reuse `Admin::BaseController` (session auth, `current_admin` → `AdminUser`, CSRF, `admin` layout). Admin panel ships **no JavaScript** (static page).
- **Branch `feat/m37-money-overview` off `main`** (already created; M33–M36 are on main). Local commits only — no push, no merge (user reviews/merges). M37 commits never stage `Gemfile.lock` (the local downgrade stays unstaged).

## Review Focus

- **Non-`paid` payments excluded:** a `pending`, `failed`, or `refunded` subscription payment must NOT move any total — only `status = 'paid'` counts. Test in Task 1.
- **`order` payments excluded:** a `purpose = 'order'` payment (meal order) must NOT appear in the money totals — only `purpose = 'subscription'`. Test in Task 1.
- **Drift from M24:** a coach's overview row (gross/commission/net) must equal that coach's `CoachApp::Earnings.summary(coach)[:summary]` for the same data. Test in Task 1.
- **Multiple paid payments / multiple coaches:** two coaches each with paid subscriptions produce two correct rows and correct CoachNa-wide totals (sum across), ordered by income desc. Test in Task 1.
- **Empty / zero state:** with no paid subscription payments, totals are all zero and the page shows an empty-state line, not a crash or a blank table. Totals test in Task 1; view test in Task 2.
- **Admin-gated:** an unauthenticated `GET` of the money page redirects to `/admin/login`, leaking nothing. Test in Task 2.

---

### Task 1: `Admin::MoneyOverview` service (one grouped aggregate, M24-pinned)

**Files:**
- Create: `app/services/admin/money_overview.rb`
- Test: `test/services/admin/money_overview_test.rb`

**Interfaces:**
- Consumes: `Payment`, `Subscription`, `Coach` (+ `CoachApp::Earnings` in the parity test only).
- Produces: `Admin::MoneyOverview.call` → an object with:
  - `.totals` responding to `gross_piastres`, `commission_piastres`, `net_piastres`, `coach_count`, `subscription_count` (all integers).
  - `.coaches` → an Array of entries (income desc), each responding to `coach_id`, `coach_name`, `gross_piastres`, `commission_piastres`, `net_piastres`, `subscription_count`.
  - `net_piastres == gross_piastres - commission_piastres` per entry and in totals; `coach_count == coaches.size`; `subscription_count == coaches.sum(&:subscription_count)`.
  - Consumed by `Admin::MoneyController` (Task 2).

- [ ] **Step 1: Write failing tests** (plain `ActiveSupport::TestCase`; reuse the earnings/M36 seeding shape — unique phones, a `Coach`/`Client`/`CoachPackage`/`Subscription`, and `Payment.create!(client_id:, purpose:, subscription_id:, amount_piastres:, provider:, status:, paid_at:)`):
  - **two coaches, income-desc order + totals:** coach A with one paid sub (gross 50000, commission 5000) and coach B with one paid sub (gross 80000, commission 12000) → `coaches` is `[B, A]` (80000 first); `totals.gross_piastres == 130000`, `totals.commission_piastres == 17000`, `totals.net_piastres == 113000`, `totals.coach_count == 2`, `totals.subscription_count == 2`.
  - **only paid counts:** add a `pending`, a `failed`, and a `refunded` subscription payment for coach A → A's row and the totals are unchanged from a single paid payment.
  - **orders excluded:** add a `purpose: "order"` paid payment (with `order_id`, no `subscription_id`) → totals unchanged.
  - **net identity:** for every entry and for totals, `net_piastres == gross_piastres - commission_piastres`.
  - **M24 parity:** for a coach with two paid subscriptions, the overview entry's `gross/commission/net` equal `CoachApp::Earnings.summary(coach)[:summary]` `grossPiastres/commissionPiastres/netPiastres`, and `subscription_count` equals that summary's `subscriptionCount`.
  - **empty:** with no paid subscription payments, `coaches == []` and every `totals.*` figure is `0`.
- [ ] **Step 2: Run** `bin/rails test test/services/admin/money_overview_test.rb` — Expected: FAIL (no service).
- [ ] **Step 3:** Implement `Admin::MoneyOverview.call` with ONE aggregate query: `Payment.where(purpose: "subscription", status: "paid").joins(subscription: :coach).group("coaches.id", "coaches.full_name").pluck(Arel.sql("coaches.id"), Arel.sql("coaches.full_name"), Arel.sql("SUM(payments.amount_piastres)"), Arel.sql("SUM(subscriptions.commission_piastres)"), Arel.sql("COUNT(*)"))`. Map rows → entries (`net = gross - commission`), sort by gross desc, build totals by summing. Use `Struct`/`Data` for `totals` and the entries so tests can call the readers. Guard integer math (the `SUM`s come back as integers for integer columns; cast with `.to_i` to be safe).
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (local): `git add app/services/admin/money_overview.rb test/services/admin/money_overview_test.rb docs/superpowers/specs/2026-11-25-m37-money-overview-design.md docs/superpowers/plans/2026-11-25-m37-money-overview.md`

---

### Task 2: Money overview page — controller, route, view, nav

**Files:**
- Create: `app/controllers/admin/money_controller.rb` (`index`)
- Create: `app/views/admin/money/index.html.erb`
- Modify: `config/routes.rb` (one GET route in the `admin` scope)
- Modify: `app/views/layouts/admin.html.erb` (nav link to Money)
- Test: `test/controllers/admin/money_controller_test.rb`

**Interfaces:**
- Consumes: `Admin::BaseController` (`current_admin`, `require_admin`), `Admin::MoneyOverview` (Task 1).
- Produces:
  - Route (inside `scope path: "admin", module: "admin", as: "admin"`): `get "money", to: "money#index", as: :money` → helper `admin_money_path`.
  - `#index` — `@overview = Admin::MoneyOverview.call`.
  - View: a totals banner (Gross income, CoachNa commission, Owed to coaches — EGP; plus the paid-subscription count) and a per-coach table (Coach, Income, CoachNa commission, Owed, Paid subs), with an empty-state line "No paid subscriptions yet." when `@overview.coaches` is empty. Nav gains a **Money** link.

- [ ] **Step 1: Write failing integration tests** (sign-in helper as in `test/controllers/admin/subscriptions_controller_test.rb`; seed with the Task 1 shape):
  - signed-in `GET admin_money_path` → `:ok`; with coach A (paid, gross 50000 / commission 5000) the body shows the coach's name, "EGP 500.00" (gross) and "EGP 450.00" (net), and a CoachNa-commission figure "EGP 50.00".
  - empty state: with no paid subscription payments, body includes "No paid subscriptions yet." and still `:ok`.
  - unauthenticated `GET admin_money_path` → redirect to `/admin/login`.
- [ ] **Step 2: Run** `bin/rails test test/controllers/admin/money_controller_test.rb` — Expected: FAIL (no route/controller).
- [ ] **Step 3:** Add the route; create the controller `#index`; create `index.html.erb` (totals banner + per-coach table + empty state, money via `number_to_currency(… / 100.0, unit: "EGP ", precision: 2)`); add a `link_to "Money", admin_money_path` to the admin layout nav after Subscriptions.
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (local).
