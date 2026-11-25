# M36 — Admin panel: subscriptions overview (read-only lookup) — Design

> Status: self-approved (user is AFK and authorized autonomous execution of M36: "make plan for m36 and implement it, I'm away from laptop"). Date: 2026-11-25. Milestone: M36 (fourth admin milestone, follows M35). Mirrors the M33/M35 AFK self-approval pattern.

## Intent and why

Clients subscribe to coaches (table `subscriptions`, owned by the Node API), and each subscription moves through a lifecycle and carries a payment. The CoachNa team has **no way to look up a subscription today** — the admin panel only lists coaches awaiting review (M33) and moderates reviews (M35). Roadmap M36: "All subscriptions … with search and status. **Done when:** the team can look up any subscription." M36 gives a signed-in admin a **read-only subscriptions overview** in the Rails admin panel: a searchable, status-filterable list, and a detail page showing the subscription's lifecycle, its coach and client, and its payment(s).

## Goals

- A signed-in admin sees a **list of all subscriptions**, newest first, each row showing the client, the coach, the package, the status, the price, and the start/end dates, linking to a detail page.
- The admin can **search** the list by client name, client phone, or coach name, and **filter by status** (the subscription lifecycle statuses). Search + filter combine.
- A subscription **detail page** shows: the subscription's status, price, commission (percent + amount), start/end dates, questionnaire-submitted time, and created time; the **client** (name, phone, email if present); the **coach** (name, phone); the **package** (name, duration, price); and the subscription's **payment(s)** (amount, status, provider, method, provider ref, paid-at, failure reason).
- The full test suite stays green; the Node API, coach app, and client app are unchanged.

## Non-goals (this milestone)

- **Meal orders** overview — deferred (roadmap: Part 1 M10–15 paused, Part 3 not started; added when orders exist). M36 is subscriptions only.
- **Any mutation of a subscription** — no cancel, no refund, no status change, no payment action. M36 is strictly read-only. (Subscription lifecycle is Node-owned; changing it is out of scope and would need Node work.)
- **Client-account actions** (suspend/reactivate) — that is M37b.
- **Coach money / earnings totals** — that is M37.
- **Pagination.** YAGNI for v1; add later if the list grows. Search + status filter are the lookup tools for now.
- **Restaurant subscriptions** — N/A (restaurants have no subscriptions); restaurant oversight is Part 3.

## Anti-goals (would make this a failure even if it "works")

- **Writing to any Node-owned table.** M36 only reads `subscriptions`, `clients`, `coaches`, `coach_packages`, `payments`. No `INSERT`/`UPDATE`/`DELETE`, no schema change, no migration, no new table. The only Rails change to a model is an **additive `has_many :payments`** association on `Subscription` (no DB effect).
- **Leaking the overview to anyone not signed in as an admin** — every action is behind `require_admin` (the `Admin::BaseController`).
- **An N+1 across the list** — the index eager-loads the client, coach, and package it displays.
- **Misreporting money.** Prices/commissions/payment amounts are stored in **piastres** (integer, 1 EGP = 100 piastres); the UI must divide by 100 and label the unit, never show raw piastres as if they were pounds.

## Constraints

- **English-only** admin UI (as M33/M34/M35). No coach/client-facing copy (no notifications — M36 sends none).
- **Shared Postgres; everything M36 reads already exists and is Node-owned:**
  - `subscriptions` — `client_id`, `coach_id`, `package_id`, `status text`, `price_piastres int`, `commission_percent numeric(5,2)`, `commission_piastres int`, `starts_at`, `ends_at`, `questionnaire_submitted_at`, `created_at`.
  - Status values (from `coaches_api/src/db/schema/subscriptions.ts`): `pending_payment`, `awaiting_questionnaire`, `awaiting_plan`, `active` (the "current" set) and `ended`, `cancelled`, `payment_failed` (not current). The status filter offers exactly these seven.
  - `clients` — `full_name`, `phone`, `email`. `coaches` — `full_name`, `phone`. `coach_packages` — `name`, `duration_days`, `price_piastres`.
  - `payments` — `amount_piastres`, `status` (`pending`/`paid`/`failed`/`refunded`), `provider`, `method`, `provider_ref`, `paid_at`, `failure_reason`, `created_at`; a subscription's payments are `payments.subscription_id = subscription.id`.
- **No schema change, no migration, no new table, no Node change.**
- Reuse the M33 admin stack: `Admin::BaseController` (session auth, `current_admin` → `AdminUser`, CSRF, the `admin` layout), the existing Rails models (`Subscription`, `Client`, `Coach`, `CoachPackage`, `Payment`), and the `admin` route scope. Money is rendered with Rails' built-in `number_to_currency(piastres / 100.0, unit: "EGP ", precision: 2)` — no new helper needed.
- Admin panel ships **no JavaScript**: the search/filter form is a plain GET `<form>` that reloads the page; no client-side filtering.
- **Branch `feat/m36-subscriptions-overview` off `main`** (M36 depends only on M33's admin auth, already on main; independent of the unmerged M34 and M35 branches). Local commits only — no push, no merge (the user reviews/merges). The M35 branch's uncommitted `Gemfile.lock` downgrade leak was stashed before branching so M36's `Gemfile.lock` matches `main`.

## Approaches considered

Where the list query + search/filter live, for a strictly read-only feature:

- **A — Thin controller builds the query; ERB renders (CHOSEN).** `Admin::SubscriptionsController#index` builds an `ActiveRecord::Relation` (eager-loaded, status-scoped, search-filtered, ordered) and `#show` loads one subscription with its associations; two ERB views render. Matches M33 exactly (its `CoachesController` is a two-line query + ERB). No service layer because there is no business logic — just reads and display. Cheapest, consistent with the panel.
- **B — Extract a `Admin::SubscriptionQuery` / serializer object.** Warranted when query logic is complex or reused; here it is one scope chain used in one place. Over-abstraction for v1 (YAGNI). Rejected, but the search/status logic goes in **model scopes** (`Subscription.for_status`, `Subscription.search`) so it is unit-testable without the controller — a middle ground that keeps the controller thin without a new object.
- **C — A Node read endpoint the Rails UI calls.** Adds runtime Rails→Node coupling and a service-auth channel for data Rails can already read directly from the shared DB. Breaks the self-contained-Rails-admin model (same reason B/C were rejected in M35). Rejected.

**Chosen: A** (with search/status as model scopes), decided 2026-11-25. There is one sensible way here — a read-only list + detail mirroring M33 — so the alternatives are recorded only to show why no service/Node layer was added.

## The design (decided)

### Model — `Subscription`
Add `has_many :payments` (additive; `Payment` already `belongs_to :subscription`). Add two scopes:
- `scope :for_status, ->(s) { where(status: s) if s.present? }` — no-op when blank (the "All" filter).
- `scope :search, ->(q) { … }` — when `q` is present, join `clients` and `coaches` and match `clients.full_name ILIKE %q%` OR `clients.phone ILIKE %q%` OR `coaches.full_name ILIKE %q%`. (Use `where("… ILIKE ?", "%#{sanitize_sql_like(q)}%")`.) No-op when blank.

### List — `Admin::SubscriptionsController#index`
`@subscriptions = Subscription.includes(:client, :coach, :coach_package).for_status(params[:status]).search(params[:q]).order(created_at: :desc)`. Exposes `params[:q]` and `params[:status]` to the view to keep the form populated. The view:
- A GET `<form>` with a text input (`q`, placeholder "Client name, phone, or coach") and a `<select>` (`status`) listing "All statuses" + the seven statuses, plus a submit button.
- A table: Client, Coach, Package, Status, Price (EGP), Started, Ends, Created; each row links to `admin_subscription_path`. Empty state ("No subscriptions match." / "No subscriptions yet.") when the relation is empty.

### Detail — `Admin::SubscriptionsController#show`
`@subscription = Subscription.includes(:client, :coach, :coach_package, :payments).find(params[:id])`. The view renders the subscription fields, the client block, the coach block, the package block, and a payments table (or "No payments recorded." when none). Dates via `strftime("%Y-%m-%d %H:%M")` (matching M33); money via `number_to_currency(… / 100.0, unit: "EGP ", precision: 2)`. `ActiveRecord::RecordNotFound` falls through to Rails' default 404 (no admin-specific handling needed; the action is behind `require_admin`).

### Routes (inside the existing `scope path: "admin", module: "admin", as: "admin"`)
- `get "subscriptions", to: "subscriptions#index", as: :subscriptions` → `admin_subscriptions_path`
- `get "subscriptions/:id", to: "subscriptions#show", as: :subscription` → `admin_subscription_path`

### Admin nav
The `main` layout currently shows only the brand + logout. Add a `<nav>` (mirroring the M33/M35 style) with **Coaches** (`admin_root_path`) and **Subscriptions** (`admin_subscriptions_path`) links. (Merging M35 — which also adds a nav with a Reviews link — will produce a trivial layout conflict the user resolves, the accepted admin-branch pattern.)

## What's left to the builder

- Exact ERB markup/column order for the list and detail, consistent with `app/views/admin/coaches/{index,show}.html.erb`.
- The exact `ILIKE` SQL and how the three OR-clauses are composed (one `where` with `OR`, using `sanitize_sql_like` on the term); whether `search` joins via `joins(:client, :coach)` or an explicit `LEFT JOIN` — use inner joins since every subscription has a client and coach (both `NOT NULL`).
- Whether to show `email` on the client block only when present.
- The status `<select>` option labels (humanized, e.g. "Awaiting questionnaire") vs raw values — humanize for display, submit the raw value.
- Test seeding of a subscription (needs a `Client`, `Coach`, `CoachPackage` with the NOT-NULL columns) — follow how existing tests build these rows.
