# M37b — Clients Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Clients section to the Rails admin panel — a searchable, status-filterable list, a detail page (profile + health + subscriptions), and suspend/reactivate/deactivate status actions.

**Architecture:** Mirror the existing Coaches section. A thin `Admin::ClientsController` does list/detail; an `Admin::ClientDecision` service runs the guarded status state machine (mirroring `Admin::CoachDecision`, minus the audit row / notifications clients have no table for). The Node API already blocks non-active clients at login/refresh, so M37b only writes `clients.status` and deletes `client_refresh_tokens` rows — no Node/schema change.

**Tech Stack:** Rails 8 (server-rendered ERB admin panel, no JS beyond the inline `confirm()` guard), shared Postgres, Minitest.

**Spec:** `docs/superpowers/specs/2026-11-26-m37b-clients-management-design.md`

## Global Constraints

- No schema change, no migration, no new table, no Node change. Writes only `clients.status` and `DELETE FROM client_refresh_tokens`.
- Every action behind `require_admin` (`Admin::BaseController`).
- English-only admin UI; no client-facing copy; M37b sends no notifications.
- Reuse `status_pill` (its `PILL_KINDS` already maps active→ok, suspended→danger, deactivated→muted) and the Coaches list markup/CSS.
- Three client statuses: `active`, `suspended`, `deactivated`. Transitions: suspend `active→suspended`; reactivate `suspended→active`; deactivate `active|suspended→deactivated` (terminal).
- Leave all changes uncommitted for the user's review (standing instruction). Commit steps below stage files but DO NOT run `git commit` — the user commits. (If the user later asks to commit, the staged set per task is listed.)

## Review Focus

- **Invalid transition** (e.g. suspend an already-deactivated or already-suspended client): must flash an alert and change nothing — covered in Task 1 + Task 4.
- **Deactivated client shows no action buttons** and "No actions available…" — covered in Task 3.
- **Client with no health profile**: detail page renders "No health profile yet", not a 500 — covered in Task 3.
- **Search term containing `%` or `_`**: matched literally (escaped via `sanitize_sql_like`), not as a wildcard — covered in Task 2.
- **Signed-out access to any client action**: redirects to login and changes nothing — covered in Task 4.

---

### Task 1: `Admin::ClientDecision` service + supporting model wiring

**Files:**
- Create: `app/services/admin/client_decision.rb`
- Create: `app/models/client_refresh_token.rb`
- Modify: `app/models/client.rb` (add `has_many :subscriptions`; update the "Rails only reads it" comment to note admin writes `status`)
- Test: `test/services/admin/client_decision_test.rb`

**Interfaces:**
- Produces: `Admin::ClientDecision.suspend!(client:)`, `.reactivate!(client:)`, `.deactivate!(client:)` — each reloads and returns the client, or raises `Admin::ClientDecision::Error` on an invalid transition. `ClientRefreshToken` (`self.table_name = "client_refresh_tokens"`, `belongs_to :client`).

- [ ] **Step 1: Write the failing tests** in `test/services/admin/client_decision_test.rb`. A `make_client(status)` helper (`Client.create!(full_name:, phone:, password_hash: "h", status:)`) and a `make_token(client)` helper (`ClientRefreshToken.create!(client_id: client.id, token: SecureRandom.hex, expires_at: 1.day.from_now)`). Tests:
  - `suspend! active→suspended and deletes refresh tokens`: make active client + 2 tokens; `suspend!`; assert `client.reload.status == "suspended"` and `ClientRefreshToken.where(client_id: client.id).count == 0`.
  - `reactivate! suspended→active and leaves tokens`: make suspended client + 1 token; `reactivate!`; assert status `active` and token count still 1.
  - `deactivate! from active and from suspended, deletes tokens`: two clients; assert both become `deactivated` and tokens deleted.
  - `suspend! on deactivated raises and changes nothing`: make deactivated client; `assert_raises(Admin::ClientDecision::Error)`; assert status still `deactivated`.
  - `reactivate! on active raises`; `deactivate! on deactivated raises`.

- [ ] **Step 2: Run tests, verify they fail.** Run: `bin/rails test test/services/admin/client_decision_test.rb` — Expected: FAIL (uninitialized constant `Admin::ClientDecision` / `ClientRefreshToken`).

- [ ] **Step 3: Create `ClientRefreshToken`** (two-line model: `self.table_name`, `belongs_to :client`). **Add `has_many :subscriptions` to `Client`** and update its comment. **Implement `Admin::ClientDecision`** mirroring `Admin::CoachDecision`'s `transition!` guard: a private `transition!(client, from:, to:)` that raises `Error` unless `from.include?(client.status)`, else in a `Client.transaction` updates `client.update!(status: to)` and, when `to` is `suspended`/`deactivated`, `ClientRefreshToken.where(client_id: client.id).delete_all`; then `client.reload`. Public methods pass the `from`/`to` per the transition table above. No `reason`, no audit row, no notifications.

- [ ] **Step 4: Run tests, verify they pass.** Run: `bin/rails test test/services/admin/client_decision_test.rb` — Expected: PASS.

- [ ] **Step 5: Stage** `app/services/admin/client_decision.rb app/models/client_refresh_token.rb app/models/client.rb test/services/admin/client_decision_test.rb` (do not commit).

---

### Task 2: Clients list (index) — controller, route, nav, scopes, view

**Files:**
- Create: `app/controllers/admin/clients_controller.rb` (`index` only this task)
- Create: `app/views/admin/clients/index.html.erb`
- Modify: `app/models/client.rb` (add `for_status` + `search` scopes)
- Modify: `config/routes.rb` (clients index + show + action routes — add all now so names resolve)
- Modify: `app/views/layouts/admin.html.erb` (add the Clients nav link)
- Test: `test/controllers/admin/clients_controller_test.rb`

**Interfaces:**
- Consumes: Task 1's models.
- Produces: `Admin::ClientsController::STATUSES = %w[active suspended deactivated]`; `Client.for_status(status)`, `Client.search(q)`; routes `admin_clients_path`, `admin_client_path`, `admin_suspend_client_path`, `admin_reactivate_client_path`, `admin_deactivate_client_path`.

- [ ] **Step 1: Write failing controller tests** (`test/controllers/admin/clients_controller_test.rb`) with the sign-in helper + `make_client` pattern from `coaches_controller_test.rb`:
  - `index lists clients of every status by default` (active/suspended/deactivated all appear).
  - `index filters by status param` (`get "/admin/clients", params: {status: "suspended"}` shows only the suspended one).
  - `index searches by name/phone/email` (`params: {q: ...}`).
  - `index escapes ILIKE wildcards` (a client named `"50%% Off"` is NOT returned by `q: "%"` matching everything — assert a second plainly-named client is absent from a `q: "%"` search, i.e. `%` matched literally).
  - `index redirects to login when signed out`.

- [ ] **Step 2: Run tests, verify they fail.** Run: `bin/rails test test/controllers/admin/clients_controller_test.rb` — Expected: FAIL (routing error / uninitialized controller).

- [ ] **Step 3: Add routes** (all five, inside the existing `admin` scope, per the spec's Routes block). **Add `for_status` + `search` scopes to `Client`** (copy the shape from `Subscription.for_status`/`search`; `search` matches `clients.full_name ILIKE :like OR clients.phone ILIKE :like OR clients.email ILIKE :like`, `sanitize_sql_like` on the term). **Create `Admin::ClientsController < BaseController`** with `STATUSES` and `index` (`@status = params[:status].presence_in(STATUSES)`, `@query = params[:q].to_s.strip`, `@counts = Client.group(:status).count`, `@clients = Client.for_status(@status).search(@query).order(created_at: :desc)`). **Create `index.html.erb`** by adapting `coaches/index.html.erb`: filter tabs (All + `STATUSES` with `@counts`), the GET search form (placeholder "Search name, phone, email"), table columns Name / Status / Phone / Email / Joined (`created_at.strftime("%b %d, %Y")`), empty state "No clients match this view." **Add the Clients nav link** to `admin.html.erb` (`admin_clients_path`, a 🧑 icon, `class="active" if admin_nav_active?(:clients)`), right after the Coaches link.

- [ ] **Step 4: Run tests, verify they pass.** Run: `bin/rails test test/controllers/admin/clients_controller_test.rb` — Expected: PASS.

- [ ] **Step 5: Stage** the created/modified files (do not commit).

---

### Task 3: Client detail (show) — controller action + view

**Files:**
- Modify: `app/controllers/admin/clients_controller.rb` (add `show`)
- Create: `app/views/admin/clients/show.html.erb`
- Test: `test/controllers/admin/clients_controller_test.rb` (add show tests)

**Interfaces:**
- Consumes: Task 2's controller/routes; `Client has_one :client_health_profile`, `has_many :subscriptions`.

- [ ] **Step 1: Write failing tests:**
  - `show renders identity, health profile, and subscriptions`: a client with a `ClientHealthProfile` (DOB, gender, weight, goal) and one `Subscription` (needs a `Coach` + `CoachPackage`, built as in `subscriptions_controller_test.rb`); assert the body includes the name, the status pill text, a health field, and the coach's name.
  - `show renders "No health profile yet" when absent`: client with no profile row; assert body includes that text and responds `:ok`.

- [ ] **Step 2: Run tests, verify they fail.** Run: `bin/rails test test/controllers/admin/clients_controller_test.rb` — Expected: FAIL.

- [ ] **Step 3: Implement `show`** (`Client.includes(:client_health_profile, subscriptions: [:coach, :coach_package]).find(params[:id])`). **Create `show.html.erb`** adapting `coaches/show.html.erb`: crumbs → `admin_clients_path`; an Identity card (phone, email, verified flags, joined, `status_pill`); a Health profile card (age from `date_of_birth` — whole years, blank if nil; gender, height_cm, weight_kg, goal, target_weight_kg, activity_level; `allergies`/`avoided_foods` arrays joined with ", " or "—") or "No health profile yet"; a Subscriptions card (table: status pill, coach name, package name, started/ends, each row linking to `admin_subscription_path`) or "No subscriptions."; and an Admin-actions card — placeholder in this task (the action forms land in Task 4), e.g. render nothing actionable yet. Age helper: inline in the view or a small `admin_helper` method `age_from(dob)`.

- [ ] **Step 4: Run tests, verify they pass.** Run: `bin/rails test test/controllers/admin/clients_controller_test.rb` — Expected: PASS.

- [ ] **Step 5: Stage** files (do not commit).

---

### Task 4: Status actions — endpoints + action buttons

**Files:**
- Modify: `app/controllers/admin/clients_controller.rb` (add `suspend`, `reactivate`, `deactivate`, private `decision`)
- Modify: `app/views/admin/clients/show.html.erb` (the Admin-actions card forms)
- Test: `test/controllers/admin/clients_controller_test.rb` (add action tests)

**Interfaces:**
- Consumes: Task 1's `Admin::ClientDecision`; Task 2's routes.

- [ ] **Step 1: Write failing tests** (mirroring the coach decision controller tests):
  - `suspend sets active client to suspended` + redirects to `admin_client_path` + flashes a notice.
  - `reactivate sets suspended client to active`.
  - `deactivate sets active client to deactivated`.
  - `invalid transition flashes alert and leaves status unchanged` (POST suspend to a deactivated client; follow redirect; body includes "Cannot"; status unchanged).
  - Signed-out: `suspend/reactivate/deactivate without sign in redirects to login and changes nothing` (status unchanged).
  - View: `show for active client shows Suspend and Deactivate but not Reactivate`; `show for suspended client shows Reactivate and Deactivate`; `show for deactivated client shows "No actions available"`; `deactivate form carries the onsubmit confirm guard`.

- [ ] **Step 2: Run tests, verify they fail.** Run: `bin/rails test test/controllers/admin/clients_controller_test.rb` — Expected: FAIL.

- [ ] **Step 3: Implement the three actions** — each loads `Client.find(params[:id])` and calls the matching `Admin::ClientDecision` method inside a private `decision(client, notice){ yield; flash[:notice] = notice rescue Admin::ClientDecision::Error => e; flash[:alert] = e.message ensure redirect_to admin_client_path(client) }` helper (copy `CoachesController#decision`). **Fill the Admin-actions card** in `show.html.erb`: `if status == "active"` → Suspend (`admin_suspend_client_path`) + Deactivate (confirm-guarded, `admin_deactivate_client_path`); `elsif "suspended"` → Reactivate (`admin_reactivate_client_path`) + Deactivate (confirm-guarded); `else` → "No actions available for this client's current status." Forms are `form_with url:, method: :post` with a submit button; Deactivate carries `html: { onsubmit: "return confirm('Deactivate this client? This cannot be undone.')" }` (matching the coach reject/deactivate forms).

- [ ] **Step 4: Run the full suite, verify green.** Run: `bin/rails test` — Expected: PASS (the pre-existing `test_show_for_approved_coach...Approve` substring failure, unrelated to M37b, is the only known red; note it if present).

- [ ] **Step 5: Stage** files (do not commit).

---

## Notes for the executor
- Build `Coach`/`CoachPackage` rows in tests the way `subscriptions_controller_test.rb` / `coaches_controller_test.rb` already do (satisfy NOT-NULL columns: coach `password_hash`, package `price_piastres`/`duration_days`/`name`).
- `Client.group(:status).count` returns a hash keyed by the string status; missing statuses read as `nil` → guard with `.to_i` in the view.
- Do not add a `reason` field anywhere — the schema has nowhere to store it (see spec cut lines).
