# Admin coach detail — Profile + Clients tabs

## Intent & why
The admin coach detail page (`/admin/coaches/:id`) today shows one screen of coach
application data and actions. The admin also needs to see **who this coach is serving** without
digging through the all-subscriptions list and filtering by coach name. This adds a second view
to the same page: a paginated list of the coach's clients, with each name linking to the existing
client detail page.

## Goals
- Split the coach detail page into two tabs: **Profile** and **Clients**.
- **Profile** = exactly the current content (Application, Documents, Admin actions), unchanged.
- **Clients** = a paginated list of every client who has ever had a subscription with this coach,
  **defaulting to a filter of "active" clients**, with a toggle to show all.
- Each client name links to the existing `/admin/clients/:id` detail page.

## Non-goals
- No changes to the client detail page, the all-clients list, or the subscriptions list.
- No new client/subscription actions from this tab (it is read-only, like the rest of the overview).
- No pagination retrofit of other admin lists (out of scope; this page only).

## Definitions
- **A coach's client** = a distinct client who has at least one subscription row with this coach
  (`subscriptions.coach_id = :id`), any status/history.
- **"Active"** (the default filter) = the client has a subscription with this coach whose status is
  one of `active`, `awaiting_plan`, `awaiting_questionnaire` — i.e. paid and live. This excludes
  `pending_payment` (mid-checkout, not yet paid) and `ended` / `cancelled` / `payment_failed`.
  *(My call, matching the app's paid-status set `PAID_STATUSES`; say if you'd rather "active" also
  include `pending_payment`.)*
- **All** = every distinct client with any subscription to this coach.

Each row shows the client's name (linked), their account status pill, their latest
subscription-with-this-coach status, and the latest subscription's start date — enough to tell who
they are without opening the detail page.

## Constraints
- Plain server-rendered Rails + ERB, no client-side framework (matches the existing admin).
- No new gems (the admin hand-rolls everything; there is currently no pagination anywhere).
- Reuse the existing `table`, `card`, `status_pill`, `filters` styling already in the admin views.

## Approaches considered

**Tabs**
- **A. Server-rendered tabs via a `?tab=` query param (chosen).** The `show` action reads
  `params[:tab]` (`profile` default, `clients`). Both tab links are plain `<a>`s styled as tabs;
  the Clients tab also carries the filter + page params. No JS. Fits the no-JS admin and is required
  anyway because pagination and filtering need server round-trips.
- B. Client-side JS toggle (both tabs rendered, CSS show/hide). Rejected: still needs server trips
  for paging/filtering, and introduces JS the admin otherwise avoids.

**Pagination**
- **A. Hand-rolled `limit`/`offset` with a page param (chosen).** A small `page`/`per_page` (25)
  with Prev/Next links. Matches the house style (no gems) and the dataset per coach is small.
- B. Add the Pagy gem. Rejected: new dependency for one page; the project avoids extra gems.

**The coach→clients query**
- Distinct clients via a join from `subscriptions` to `clients` filtered by `coach_id`, with the
  "active" filter applied as a `WHERE subscriptions.status IN (...)` and `DISTINCT` on client.
  Latest-subscription fields come from the newest subscription row per client with this coach.

## How it gets built (the decided parts)
- **Route:** none added — reuse `GET /admin/coaches/:id` (`admin_coach_path`). `tab`, `filter`,
  and `page` are query params.
- **Controller (`Admin::CoachesController#show`):** when `tab == "clients"`, build
  `@client_rows` (distinct clients for this coach, filtered by `@client_filter` which defaults to
  `"active"`), plus `@page` / `@total_pages` for the 25-per-page window. Profile tab skips the query.
- **Model/scope:** add a query on `Coach` (or a small query object under `app/services/admin/`)
  returning a coach's clients with their latest-subscription status/date, honoring the filter and
  `limit`/`offset`. Count query for total pages.
- **View (`show.html.erb`):** a tab bar at the top (two links). Extract the current body into a
  `profile` partial; add a `clients` partial with the filter control (Active | All), the table, and
  Prev/Next pager. Tab/filter/page state is preserved in the links.

## What's left to the builder
- Exact SQL shape of the distinct-clients-with-latest-subscription query (window function vs.
  grouped subquery) — builder's call, whichever is clearest.
- Tab-bar markup/CSS detail, reusing existing admin styles.
- Empty states ("No active clients." / "No clients yet.").
