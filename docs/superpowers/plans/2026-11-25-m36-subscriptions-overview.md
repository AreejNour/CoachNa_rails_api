# M36 — Admin subscriptions overview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A signed-in admin can look up any subscription in the Rails admin panel — a searchable, status-filterable list, and a detail page showing the subscription's lifecycle, its coach, client, package, and payment(s).

**Architecture:** Read-only. A thin `Admin::SubscriptionsController` (`index` + `show`) drives two server-rendered ERB views; search and status-filter live in `Subscription` model scopes so they are unit-testable. No service layer (no business logic), no Node code, no schema change. The only model change is an additive `has_many :payments` on `Subscription`.

**Tech Stack:** Rails 8 (minitest), ERB views, shared Postgres, M33 admin session stack (`Admin::BaseController`, `AdminUser`, CSRF, `admin` layout).

**Spec:** `docs/superpowers/specs/2026-11-25-m36-subscriptions-overview-design.md`

## Global Constraints

- **English-only** admin UI. No coach/client notifications (M36 sends none).
- **Read-only. No schema change, no migration, no new table, no Node change.** M36 only reads `subscriptions`, `clients`, `coaches`, `coach_packages`, `payments`. The one model change is an additive `has_many :payments` on `Subscription` (no DB effect).
- Money is stored in **piastres** (integer, 1 EGP = 100 piastres). Render with `number_to_currency(piastres / 100.0, unit: "EGP ", precision: 2)` — never show raw piastres as pounds.
- Subscription status values (exactly these seven, from `coaches_api/src/db/schema/subscriptions.ts`): `pending_payment`, `awaiting_questionnaire`, `awaiting_plan`, `active`, `ended`, `cancelled`, `payment_failed`.
- Reuse `Admin::BaseController` (session auth, `current_admin` → `AdminUser`, CSRF, `admin` layout) and existing models (`Subscription`, `Client`, `Coach`, `CoachPackage`, `Payment`). Admin panel ships **no JavaScript** — search/filter is a plain GET form.
- **Branch `feat/m36-subscriptions-overview` off `main`** (already created; independent of the unmerged M34/M35 branches). Local commits only — no push, no merge (user reviews/merges).

## Review Focus

- **Search term with a `%` or `_`** (ILIKE wildcards) must be matched literally, not as a wildcard — the scope uses `sanitize_sql_like` on the term. Test in Task 1.
- **Blank / absent `q` and `status` params** must return the full list unfiltered, not an empty list or an error — both scopes are no-ops when blank. Test in Task 1.
- **Unknown/garbage `status` value** returns an empty list (no match), never an error. Test in Task 1.
- **A subscription with zero payments** renders the detail page with a "No payments recorded." line, not a crash or blank. Test in Task 3.
- **Every action is admin-gated** — an unauthenticated `GET` of the list or a detail page redirects to `/admin/login`, leaking nothing. Test in Tasks 2 and 3.

---

### Task 1: `Subscription` scopes + `has_many :payments`

**Files:**
- Modify: `app/models/subscription.rb`
- Test: `test/models/subscription_test.rb` (create)

**Interfaces:**
- Produces:
  - `Subscription.for_status(status)` — `where(status:)` when `status` present; the unscoped relation when blank/nil.
  - `Subscription.search(q)` — when `q` present, inner-joins `clients` and `coaches` and returns subscriptions whose `clients.full_name`, `clients.phone`, or `coaches.full_name` matches `%q%` case-insensitively (ILIKE), with `q` escaped via `sanitize_sql_like`; the unscoped relation when blank/nil.
  - `Subscription#payments` → the subscription's `Payment` records (`has_many :payments`).
- Consumed by `Admin::SubscriptionsController` (Tasks 2–3).

- [ ] **Step 1: Write failing tests** (plain `ActiveSupport::TestCase`). Add a helper that seeds a full subscription given names:
  ```ruby
  def make_subscription(client_name:, coach_name:, client_phone: "+201000000001", status: "active")
    coach  = Coach.create!(full_name: coach_name, phone: "+20100#{rand(1000000..9999999)}", password_hash: "h", status: "approved")
    client = Client.create!(full_name: client_name, phone: client_phone, password_hash: "h")
    pkg    = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: 50000, duration_days: 30, includes: {})
    Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: status,
                         price_piastres: 50000, commission_percent: 10, commission_piastres: 5000,
                         starts_at: Time.current, ends_at: 30.days.from_now)
  end
  ```
  Cases:
  - `for_status("active")` returns only the active subscription, excludes an `ended` one; `for_status(nil)` and `for_status("")` return both; `for_status("bogus")` returns none.
  - `search("Layla")` (client full_name) returns the matching subscription and excludes a non-matching one; `search` by client phone fragment matches; `search` by coach full_name matches; `search(nil)`/`search("")` return all.
  - `search("50%")` on a client literally named `"50% Off"` matches that client and does **not** wildcard-match others (escaping check).
  - a `Payment.create!(subscription: sub, client_id: sub.client_id, purpose: "subscription", amount_piastres: 50000, provider: "paymob", status: "paid")` is returned by `sub.payments`.
- [ ] **Step 2: Run** `bin/rails test test/models/subscription_test.rb` — Expected: FAIL (no scopes / no `payments` assoc).
- [ ] **Step 3:** Add `has_many :payments` and the two scopes to `app/models/subscription.rb`. For `search`, compose one `where` with three `ILIKE ?` OR-clauses over `joins(:client, :coach)`, binding `"%#{sanitize_sql_like(q)}%"`; guard both scopes with `if <arg>.present?` (return `all` otherwise).
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (local): `git add app/models/subscription.rb test/models/subscription_test.rb`

---

### Task 2: Subscriptions list — controller `#index`, route, view, nav

**Files:**
- Create: `app/controllers/admin/subscriptions_controller.rb` (`index`)
- Create: `app/views/admin/subscriptions/index.html.erb`
- Modify: `config/routes.rb` (one GET route in the `admin` scope)
- Modify: `app/views/layouts/admin.html.erb` (nav with Coaches + Subscriptions)
- Test: `test/controllers/admin/subscriptions_controller_test.rb` (create)

**Interfaces:**
- Consumes: `Admin::BaseController` (`current_admin`, `require_admin`), `Subscription` scopes (Task 1).
- Produces:
  - Route (inside `scope path: "admin", module: "admin", as: "admin"`): `get "subscriptions", to: "subscriptions#index", as: :subscriptions` → helper `admin_subscriptions_path`.
  - `#index` — `@subscriptions = Subscription.includes(:client, :coach, :coach_package).for_status(params[:status]).search(params[:q]).order(created_at: :desc)`; `params[:q]`/`params[:status]` available to the view.

- [ ] **Step 1: Write failing integration tests** (sign-in helper as in `test/controllers/admin/coaches_controller_test.rb`: `AdminUser.create!(email:, name:, password:)` then `post "/admin/login"`; seed subscriptions with the Task 1 helper shape):
  - signed-in `GET admin_subscriptions_path` → `:ok`, body includes a seeded client's and coach's names.
  - `?status=active` lists the active subscription and excludes an `ended` one (assert the excluded client's name absent).
  - `?q=<client name>` lists the matching subscription and excludes a non-matching one.
  - empty state: with no subscriptions, body includes "No subscriptions".
  - unauthenticated `GET admin_subscriptions_path` → redirect to `/admin/login`.
- [ ] **Step 2: Run** `bin/rails test test/controllers/admin/subscriptions_controller_test.rb` — Expected: FAIL (no route/controller).
- [ ] **Step 3:** Add the route; create the controller `#index`; create `index.html.erb` — a GET `<form>` (text `q` with placeholder "Client name, phone, or coach"; `<select name="status">` with an "All statuses" blank option + the seven statuses, humanized labels / raw values, re-selecting `params[:status]`; submit button) and a table (Client, Coach, Package, Status, Price, Started, Ends, Created) linking each row to `admin_subscription_path(sub)`, with an empty-state line. Add a `<nav>` to the admin layout with `link_to "Coaches", admin_root_path` and `link_to "Subscriptions", admin_subscriptions_path` (mirror the existing header styling).
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (local).

---

### Task 3: Subscription detail — controller `#show`, route, view

**Files:**
- Modify: `app/controllers/admin/subscriptions_controller.rb` (`show`)
- Create: `app/views/admin/subscriptions/show.html.erb`
- Modify: `config/routes.rb` (one GET route in the `admin` scope)
- Test: `test/controllers/admin/subscriptions_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `Subscription` (`has_many :payments`, Task 1); `current_admin`.
- Produces:
  - Route: `get "subscriptions/:id", to: "subscriptions#show", as: :subscription` → helper `admin_subscription_path`.
  - `#show` — `@subscription = Subscription.includes(:client, :coach, :coach_package, :payments).find(params[:id])`.

- [ ] **Step 1: Write failing tests** (extend the Task 2 file):
  - signed-in `GET admin_subscription_path(sub)` → `:ok`; body shows the status, the client name + phone, the coach name, the package name, and the price (formatted, e.g. "EGP 500.00").
  - with a `paid` `Payment` on the subscription, the detail body shows the payment amount and its status ("paid"); with **no** payments, the body includes "No payments recorded." and still returns `:ok`.
  - unauthenticated `GET admin_subscription_path(sub)` → redirect to `/admin/login`.
- [ ] **Step 2: Run** the test — Expected: FAIL (no `show` route/action/view).
- [ ] **Step 3:** Add the route; add `#show`; create `show.html.erb` rendering the subscription fields (status; price, commission_percent + commission_piastres, dates via `strftime("%Y-%m-%d %H:%M")`, questionnaire_submitted_at, created_at), a client block (full_name, phone, email only when present), a coach block (full_name, phone), a package block (name, duration_days, price), and a payments table (amount, status, provider, method, provider_ref, paid_at, failure_reason) with a "No payments recorded." fallback. Money via `number_to_currency(… / 100.0, unit: "EGP ", precision: 2)`.
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (local).
