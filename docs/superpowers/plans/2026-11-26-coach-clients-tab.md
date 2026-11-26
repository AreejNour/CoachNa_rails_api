# Admin Coach Detail — Profile + Clients Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Clients tab to the admin coach detail page showing a paginated, filterable list of the coach's clients, each name linking to the client detail page.

**Architecture:** Server-rendered tabs on the existing `GET /admin/coaches/:id` via a `?tab=` query param — no new route, no JS. A query object, `Admin::CoachClientsQuery`, returns one row per distinct client of the coach (filtered to "active" by default) with that client's latest subscription-with-this-coach status and start date, plus the total for a hand-rolled 25-per-page limit/offset pager. The controller calls it only on the Clients tab; the view splits into a `profile` partial (today's content, unchanged) and a `clients` partial.

**Tech Stack:** Rails 7 (server-rendered ERB), Minitest integration/unit tests, Postgres (shared dev DB `coacha`, owned by the Node API — never reset from Rails).

**Spec:** `docs/superpowers/specs/2026-11-26-coach-clients-tab-design.md`

## Global Constraints

- No new gems — the admin hand-rolls pagination; no Pagy/Kaminari. (Spec: "No new gems".)
- No new route — reuse `GET /admin/coaches/:id` (`admin_coach_path`); `tab`, `filter`, `page` are query params. (Spec: "Route: none added".)
- Read-only — this tab adds no client/subscription actions. (Spec: Non-goals.)
- Reuse existing admin styles: `table`, `card`, `status_pill`, `filters`. (Spec: Constraints.)
- `subscriptions`, `clients`, `coaches` tables are owned by the Node API; Rails only reads them here. Rails migrations must not touch them.
- "Active" subscription statuses = `active`, `awaiting_plan`, `awaiting_questionnaire` (the paid-and-live set). Excludes `pending_payment`, `ended`, `cancelled`, `payment_failed`. (Spec: Definitions.)
- Page size = 25.

## Review Focus

- **Coach with zero clients** → Clients tab shows "No clients yet." (empty state), not a crash or blank table. Covered in Task 2.
- **Active filter default when `filter` param absent** → defaults to "active", so a coach whose only subscription is `pending_payment` or `ended` shows "No active clients." while "All" reveals them. Covered in Tasks 1 & 2.
- **A client with multiple subscriptions to the same coach** → the row shows the *latest* subscription's status/start date (newest `starts_at` wins), and the client appears once. Covered in Task 1.
- **`page` out of range or non-numeric** (`?page=0`, `?page=999`, `?page=abc`) → clamps to a valid page (min 1, no past-the-end offset), never errors. Covered in Task 2.
- **Unknown `tab` value** (`?tab=bogus`) → falls back to the Profile tab. Covered in Task 2.

---

### Task 1: `Admin::CoachClientsQuery` query object

**Files:**
- Create: `app/services/admin/coach_clients_query.rb`
- Test: `test/services/admin/coach_clients_query_test.rb`

**Interfaces:**
- Consumes: `Coach`, `Client`, `Subscription`, `CoachPackage` models (existing).
- Produces:
  - `Admin::CoachClientsQuery::ACTIVE_STATUSES` → `%w[active awaiting_plan awaiting_questionnaire]`.
  - `Admin::CoachClientsQuery.call(coach:, filter: "active", page: 1, per_page: 25)` → a `Result`.
  - `Result` = `Struct.new(:rows, :total, :page, :total_pages, keyword_init: true)`.
  - `Row` = `Struct.new(:client, :latest_status, :latest_started_at, keyword_init: true)`.
  - Semantics: `rows` holds one `Row` per distinct client of `coach`, ordered by `client.full_name` ascending, windowed to the requested page. `filter == "active"` keeps only clients who have at least one subscription-with-this-coach whose status is in `ACTIVE_STATUSES`; any other `filter` value means "all" (every distinct client with any subscription to the coach). `latest_status`/`latest_started_at` come from that client's newest subscription *with this coach* (max `starts_at`). `total` is the distinct-client count after filtering (not page-limited). `page` is the clamped page actually returned; `total_pages` = `(total / per_page.to_f).ceil`, minimum 1.

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Admin::CoachClientsQueryTest < ActiveSupport::TestCase
  @@seq = 0
  def nxt; @@seq += 1; end
  def uniq_phone; format("+20100%07d", nxt); end

  def make_coach(name = "Coach")
    Coach.create!(full_name: name, phone: uniq_phone, password_hash: "h", status: "approved")
  end

  def make_client(name)
    Client.create!(full_name: name, phone: uniq_phone, password_hash: "h")
  end

  def sub(coach, client, status:, starts_at: Time.current)
    pkg = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: 50_000,
                               duration_days: 30, includes: {})
    Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: status,
                         price_piastres: 50_000, commission_percent: 10, commission_piastres: 5_000,
                         starts_at: starts_at, ends_at: starts_at + 30.days)
  end

  test "active filter keeps only clients with a live subscription to this coach" do
    coach = make_coach
    live  = make_client("Live Lara"); sub(coach, live, status: "active")
    ended = make_client("Ended Ed");  sub(coach, ended, status: "ended")

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "active")

    assert_equal ["Live Lara"], result.rows.map { |r| r.client.full_name }
    assert_equal 1, result.total
  end

  test "all filter returns every distinct client of the coach" do
    coach = make_coach
    live  = make_client("Live Lara"); sub(coach, live, status: "active")
    ended = make_client("Ended Ed");  sub(coach, ended, status: "ended")

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all")

    assert_equal ["Ended Ed", "Live Lara"], result.rows.map { |r| r.client.full_name }
    assert_equal 2, result.total
  end

  test "a client with multiple subs to the coach appears once with the latest status and date" do
    coach = make_coach
    cli = make_client("Repeat Rae")
    sub(coach, cli, status: "ended", starts_at: 90.days.ago)
    sub(coach, cli, status: "active", starts_at: 2.days.ago)

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all")

    assert_equal 1, result.rows.length
    assert_equal "active", result.rows.first.latest_status
    assert_in_delta 2.days.ago.to_f, result.rows.first.latest_started_at.to_f, 5
  end

  test "excludes clients of other coaches" do
    coach = make_coach("Mine")
    other = make_coach("Other")
    mine  = make_client("Mine Mia");   sub(coach, mine, status: "active")
    theirs = make_client("Their Tom"); sub(other, theirs, status: "active")

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all")

    assert_equal ["Mine Mia"], result.rows.map { |r| r.client.full_name }
  end

  test "paginates: total counts all, rows are limited to the page window" do
    coach = make_coach
    3.times { |i| sub(coach, make_client(format("Client %02d", i)), status: "active") }

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all", page: 1, per_page: 2)

    assert_equal 3, result.total
    assert_equal 2, result.rows.length
    assert_equal 2, result.total_pages
    assert_equal 1, result.page
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/admin/coach_clients_query_test.rb`
Expected: FAIL with `uninitialized constant Admin::CoachClientsQuery`.

- [ ] **Step 3: Implement `Admin::CoachClientsQuery.call` in `app/services/admin/coach_clients_query.rb`**

Build the distinct-client set from `coach.subscriptions`: when `filter == "active"`, restrict to `where(status: ACTIVE_STATUSES)`; pluck distinct `client_id` from that scope to get `total` and the id set. Load the page of clients with `Client.where(id: ids).order(:full_name).limit(per_page).offset((page-1)*per_page)` (clamp `page` to `1..total_pages`). For those page clients, fetch the latest subscription-with-this-coach per client — use Postgres `DISTINCT ON (client_id)` ordered by `client_id, starts_at DESC` over `coach.subscriptions.where(client_id: page_ids)` — and map each client to a `Row` with that subscription's `status`/`starts_at`. Return the `Result`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/admin/coach_clients_query_test.rb`
Expected: PASS (5 runs, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/services/admin/coach_clients_query.rb test/services/admin/coach_clients_query_test.rb
git commit -m "feat(admin): coach→clients query object for the Clients tab"
```

---

### Task 2: Tabs on the coach detail page (controller + views)

**Files:**
- Modify: `app/controllers/admin/coaches_controller.rb` (`show` action)
- Modify: `app/views/admin/coaches/show.html.erb` (add tab bar, render partials)
- Create: `app/views/admin/coaches/_profile.html.erb` (today's detail body, moved verbatim)
- Create: `app/views/admin/coaches/_clients.html.erb` (filter control, table, pager)
- Modify: `test/controllers/admin/coaches_controller_test.rb`

**Interfaces:**
- Consumes: `Admin::CoachClientsQuery.call(coach:, filter:, page:, per_page:)` and its `Result`/`Row` from Task 1; `admin_coach_path`, `admin_client_path`; `status_pill` helper.
- Produces: no new public interface (a page).

Controller `show`: set `@tab = params[:tab] == "clients" ? "clients" : "profile"`. When `@tab == "clients"`, set `@client_filter = params[:filter] == "all" ? "all" : "active"`, `@page = params[:page].to_i` (treated via the query's clamping; pass raw and let the query clamp, or clamp to `>= 1` here), and `@clients = Admin::CoachClientsQuery.call(coach: @coach, filter: @client_filter, page: [@page, 1].max, per_page: 25)`. Keep `@documents` load as today (Profile tab needs it).

View `show.html.erb`: keep crumbs + page-head; add a tab bar — two `link_to`s to `admin_coach_path(@coach)` (Profile) and `admin_coach_path(@coach, tab: "clients")` (Clients), the current one marked active. Then `render "profile"` or `render "clients"` on `@tab`. Move the existing `<div class="detail">…</div>` body into `_profile.html.erb` unchanged.

`_clients.html.erb`: an Active | All filter (two `link_to`s to `admin_coach_path(@coach, tab: "clients", filter: …)`, current one marked active); a `table` with columns Client / Account / Subscription / Started; each row links the name via `link_to row.client.full_name, admin_client_path(row.client)`, an account `status_pill(row.client.status)`, `status_pill(row.latest_status)`, and `row.latest_started_at&.strftime("%Y-%m-%d")`. Empty state: "No active clients." when filter is active, "No clients yet." when all. Prev/Next pager: `link_to` to `admin_coach_path(@coach, tab: "clients", filter: @client_filter, page: …)`, Prev hidden/disabled on page 1, Next hidden/disabled when `@clients.page >= @clients.total_pages`; show "Page X of Y".

- [ ] **Step 1: Write the failing tests**

Add to `test/controllers/admin/coaches_controller_test.rb` (reuse its `make_coach`/`sign_in`; add client+subscription helpers like Task 1's):

```ruby
test "coach show defaults to the profile tab" do
  sign_in
  coach = make_coach("Approved Amy", "approved", "+201000000050")
  get "/admin/coaches/#{coach.id}"
  assert_response :ok
  assert_includes @response.body, "Application"      # profile content
end

test "clients tab lists only active clients by default, each name linked" do
  sign_in
  coach = make_coach("Approved Amy", "approved", "+201000000051")
  live = make_client("Live Lara"); sub(coach, live, status: "active")
  ended = make_client("Ended Ed"); sub(coach, ended, status: "ended")

  get "/admin/coaches/#{coach.id}", params: { tab: "clients" }
  assert_response :ok
  assert_includes @response.body, "Live Lara"
  assert_includes @response.body, admin_client_path(live)
  assert_not_includes @response.body, "Ended Ed"
end

test "clients tab filter=all shows every client" do
  sign_in
  coach = make_coach("Approved Amy", "approved", "+201000000052")
  live = make_client("Live Lara"); sub(coach, live, status: "active")
  ended = make_client("Ended Ed"); sub(coach, ended, status: "ended")

  get "/admin/coaches/#{coach.id}", params: { tab: "clients", filter: "all" }
  assert_response :ok
  assert_includes @response.body, "Live Lara"
  assert_includes @response.body, "Ended Ed"
end

test "clients tab empty state for a coach with no clients" do
  sign_in
  coach = make_coach("Approved Amy", "approved", "+201000000053")
  get "/admin/coaches/#{coach.id}", params: { tab: "clients" }
  assert_response :ok
  assert_includes @response.body, "No active clients"
end

test "unknown tab falls back to profile" do
  sign_in
  coach = make_coach("Approved Amy", "approved", "+201000000054")
  get "/admin/coaches/#{coach.id}", params: { tab: "bogus" }
  assert_response :ok
  assert_includes @response.body, "Application"
end

test "out-of-range page does not error" do
  sign_in
  coach = make_coach("Approved Amy", "approved", "+201000000055")
  make_client("Live Lara").tap { |c| sub(coach, c, status: "active") }
  get "/admin/coaches/#{coach.id}", params: { tab: "clients", page: "999" }
  assert_response :ok
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/coaches_controller_test.rb`
Expected: FAIL (clients-tab content/links absent; `make_client`/`sub` helpers added in this step).

- [ ] **Step 3: Implement the controller and views**

Update `show` in `app/controllers/admin/coaches_controller.rb` per the Interfaces block. Create `_profile.html.erb` by moving the existing `<div class="detail">…</div>` out of `show.html.erb` verbatim. Rewrite `show.html.erb` to render the tab bar + the chosen partial. Create `_clients.html.erb` with the filter control, table, empty states, and pager described above.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/admin/coaches_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Run the full admin suite for regressions**

Run: `bin/rails test test/controllers/admin test/services/admin`
Expected: PASS (no regressions in the existing coach/subscription/client tests).

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/coaches_controller.rb app/views/admin/coaches/ test/controllers/admin/coaches_controller_test.rb
git commit -m "feat(admin): Profile + Clients tabs on the coach detail page"
```

---

## Notes for the executor

- **Standing project rule: no commit, no push.** Ignore the `git commit` steps above — leave all changes uncommitted in the working tree for the user's manual review. (The commit steps are the plan template's default; this rule overrides them.) The per-task test runs are still the gate between tasks.
- Dev DB is shared with the Node API; tests run against the test DB only — never run anything that resets the dev `coacha` database.
