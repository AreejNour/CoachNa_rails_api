# M37b — Admin panel: clients management (list + detail + status actions) — Design

> Status: self-approved (user is AFK — "away from keyboard" — after choosing "View + status actions" and seeing the full design + its three cut lines; mirrors the M33/M36 AFK self-approval pattern). The three cut lines (no audit table, no notification, no instant token kill) are kept as follow-ups — the conservative choice, since the audit trail would need a cross-repo Node migration. All changes left uncommitted for the user's review. Date: 2026-11-26. Milestone: M37b (final admin milestone; the client-account actions deferred from M36).

## Intent and why

The admin panel can manage coaches (M33/M34), moderate reviews (M35), and look up subscriptions (M36) and money (M37), but it has **no way to see or manage clients**. The CoachNa team needs to find any client and act on a problem account — a client who abuses a coach, charges back, or asks to be removed. M37b adds a **Clients** tab: a searchable, status-filterable list; a detail page showing the client's profile, health data, and subscriptions; and **status actions** (suspend / reactivate / deactivate).

The key enabler: the Node API **already blocks non-active clients at the edge** — `client-auth.service.ts#login` throws `403 "account not active"` when `status !== 'active'` (line 143), and `refresh` / `requestPasswordReset` / `confirmPasswordReset` all do the same. So flipping `clients.status` in the shared DB is sufficient to lock a client out; **no Node change is needed.**

## Goals

- A signed-in admin sees a **list of all clients**, newest first, each row showing name, status, phone, email, and join date, linking to a detail page.
- The admin can **search** by client name, phone, or email, and **filter by status** (active / suspended / deactivated) via tabs with counts. Search + filter combine. (Mirrors the Coaches list we just built.)
- A client **detail page** shows: identity (name, status, phone, email, phone/email-verified, joined); the **health profile** (age from DOB, gender, height, weight, goal, target weight, activity level, allergies, avoided foods) or "No health profile yet"; and the client's **subscriptions** (status, coach, package, price, dates), each linking to the existing subscription detail page.
- The admin can **suspend** an active client, **reactivate** a suspended client, and **deactivate** an active or suspended client. Deactivate carries a JS confirm (it is terminal). Available actions depend on current status; a deactivated client shows none.
- Suspending or deactivating **revokes the client's refresh tokens** so the session cannot be extended; login and refresh are already blocked by Node.
- The full test suite stays green; the Node API, coach app, and client app are unchanged.

## Non-goals (this milestone)

- **Editing client details** (name/email/phone) or health data — view + status only (the user picked "View + status actions", not "View + edit").
- **Persisting a reason or an audit trail** for a status change. Coaches log to `coach_status_changes`; clients have **no equivalent table and no reason column**. Adding one is a Node-owned Drizzle migration — out of scope for a Rails-only milestone. Recorded as a follow-up below.
- **Instantly killing an in-flight access token.** A short-lived client access token (JWT) stays valid until it expires; the client cannot obtain a new one once suspended. Per-request status enforcement is a Node follow-up.
- **Notifying the client** (push/email) that they were suspended/deactivated. M37b sends nothing (consistent with M36). The coach-side `CoachEvents` has no client equivalent; adding one is out of scope.
- **Deleting a client / GDPR erase** — separate, higher-risk feature.
- **Pagination** — YAGNI; search + status filter are the lookup tools, as in Coaches/M36.

## Anti-goals (would make this a failure even if it "works")

- **Any schema change, migration, new table, or Node change.** M37b writes only to `clients.status` and deletes rows from `client_refresh_tokens` (both Node-owned data, not schema). Reads `clients`, `client_health_profiles`, `subscriptions`, `coaches`, `coach_packages`.
- **Leaking the section to anyone not signed in as an admin** — every action is behind `require_admin` (`Admin::BaseController`).
- **A broken/guardless transition.** Each action validates the current status before writing (e.g. you cannot suspend a deactivated client); an invalid transition flashes an alert and changes nothing, exactly like `Admin::CoachDecision`.
- **An N+1 across the list** — the index eager-loads what it displays.

## Constraints

- **English-only** admin UI. No client-facing copy.
- **Shared Postgres, all Node-owned:**
  - `clients` — `full_name`, `phone`, `email`, `status` (enum `active` / `suspended` / `deactivated`), `phone_verified_at`, `email_verified_at`, `created_at`.
  - `client_health_profiles` — `client_id` (PK/FK), `date_of_birth`, `gender`, `height_cm`, `weight_kg`, `activity_level`, `goal`, `target_weight_kg`, `allergies jsonb`, `avoided_foods jsonb`, `completed_at`.
  - `subscriptions` — `client_id`, plus the fields M36 already renders; reuse `admin_subscription_path`.
  - `client_refresh_tokens` — `client_id`; rows deleted on suspend/deactivate.
- Reuse the existing admin stack: `Admin::BaseController`, `AdminUser`/`current_admin`, the `admin` layout + route scope, and `status_pill` (its `PILL_KINDS` already maps `active`→ok, `suspended`→danger, `deactivated`→muted).
- Admin panel ships **no JavaScript** except the existing inline `confirm()` guard used on terminal coach actions; reuse that pattern for Deactivate.
- Leave all changes **uncommitted** for the user's manual review (per standing instruction). No branch/commit/push unless asked.

## Approaches considered

- **A — Mirror the Coaches section: thin controller + a `ClientDecision` service (CHOSEN).** `Admin::ClientsController` does list/detail (like the Coaches index we just built and M36) and delegates each status action to `Admin::ClientDecision` (a guarded state machine mirroring `Admin::CoachDecision`, minus the audit row / notifications clients don't have). Consistent with the established admin pattern; the transition guard is unit-testable in isolation.
- **B — Put the status logic straight in the controller.** Fewer files, but it scatters the state-machine guard into request handling and diverges from `CoachDecision`. Rejected — the service is cheap and matches precedent.
- **C — Call a new Node endpoint to change client status.** Adds Rails→Node coupling for a write Rails can do directly on the shared DB, and the Node edge already enforces the status. Rejected (same reasoning that kept M35/M36 self-contained).

**Chosen: A**, 2026-11-26. One sensible way given the Coaches/CoachDecision precedent; alternatives recorded to show why no Node layer and no in-controller logic.

## The design (decided)

### Service — `Admin::ClientDecision`
A module mirroring `Admin::CoachDecision`, three transitions, each atomic (guard + `clients.status` update + token revocation in one transaction), raising `Admin::ClientDecision::Error` on an invalid transition:
- `suspend!(client:)` — `active → suspended`; delete the client's `client_refresh_tokens`.
- `reactivate!(client:)` — `suspended → active`; no token change (client simply logs in again).
- `deactivate!(client:)` — `active | suspended → deactivated`; delete the client's `client_refresh_tokens`.

No `admin:`-authored audit row and no `reason` (no table/column). The `admin` is still the signed-in `current_admin` performing the action; it is just not persisted.

### Models (additive, no DB effect)
- `Client` — ensure `has_many :subscriptions` and `has_one :client_health_profile`; `scope :for_status` and `scope :search` (name/phone/email `ILIKE`, using `sanitize_sql_like`), matching how the Coaches list filters.
- `ClientHealthProfile` (`self.table_name = "client_health_profiles"`) and `ClientRefreshToken` (`self.table_name = "client_refresh_tokens"`) — minimal read/delete models if they don't already exist.

### Controller — `Admin::ClientsController`
- `index` — `@status` (validated against the three statuses), `@query`, `@counts = Client.group(:status).count`, `@clients = Client.for_status(@status).search(@query).order(created_at: :desc)`.
- `show` — `Client.includes(:client_health_profile, subscriptions: [:coach, :coach_package]).find(params[:id])`.
- `suspend` / `reactivate` / `deactivate` — load the client, call the matching `ClientDecision` method inside a `decision(client, notice){ … }` helper that flashes a notice, rescues `ClientDecision::Error` to a flash alert, and redirects to `admin_client_path` — identical shape to `CoachesController#decision`.

### Views — `app/views/admin/clients/{index,show}.html.erb`
- **index** — filter tabs (All + three statuses with counts) + a GET search form + a table (Name, Status, Phone, Email, Joined), reusing the markup/CSS from the Coaches index we just added. Empty state "No clients match this view."
- **show** — a detail layout mirroring `coaches/show`: an Identity card, a Health profile card (age computed from `date_of_birth`; "No health profile yet" when the row is absent), a Subscriptions card (table linking to `admin_subscription_path`, or "No subscriptions."), and an Admin-actions card that renders Suspend (when active), Reactivate (when suspended), Deactivate (when active/suspended, behind the `onsubmit` confirm guard), or "No actions available for this client's current status." (deactivated).

### Routes (inside the existing `admin` scope)
```
get  "clients",             to: "clients#index",      as: :clients
get  "clients/:id",         to: "clients#show",       as: :client
post "clients/:id/suspend",    to: "clients#suspend",    as: :suspend_client
post "clients/:id/reactivate", to: "clients#reactivate", as: :reactivate_client
post "clients/:id/deactivate", to: "clients#deactivate", as: :deactivate_client
```

### Admin nav
Add a **Clients** link (`admin_clients_path`, a 🧑 icon) to the sidebar `nav.side`, right after Coaches, with the `active` class driven by the existing `admin_nav_active?` helper (`controller_name == "clients"`).

### Tests
- `Admin::ClientDecisionTest` — each transition succeeds from its allowed `from` states, sets the new status, deletes refresh tokens where specified, and raises on an invalid transition (e.g. suspend a deactivated client) leaving status unchanged.
- `Admin::ClientsControllerTest` — index lists all statuses by default, filters by `status`, searches by name/phone/email; show renders profile + health + subscriptions; each action transitions + redirects + flashes, guards an invalid transition, and redirects to login when signed out (changing nothing); the detail page shows the right action buttons per status and the `onsubmit` confirm guard on Deactivate.

## What's left to the builder

- Exact ERB markup/column order, consistent with `coaches/{index,show}` and `subscriptions/show`.
- Age calculation from `date_of_birth` (whole years at today's date; blank when DOB is null).
- Rendering `allergies` / `avoided_foods` JSON arrays (join with commas; "—" when empty/null).
- Whether `ClientHealthProfile` / `ClientRefreshToken` models already exist (reuse) or need the two-line `self.table_name` stub.
- Exact `ILIKE` composition for `search` (one `where` with OR across name/phone/email, `sanitize_sql_like` on the term).

## Follow-ups (noted, not in M37b)
- **Audit trail** for client status changes (who/when/why) — needs a `client_status_changes` table (Node Drizzle migration) mirroring `coach_status_changes`.
- **Client notification** on suspend/deactivate — needs a client events/push/email path.
- **Instant session kill** — per-request client status enforcement in the Node API.
