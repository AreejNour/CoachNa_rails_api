# M33 — Admin panel: team login + coach review list

_Design doc · 2026-11-24 · project_

## Intent / why

Stand up the **CoachNa admin panel** and give the team the first thing it needs: to
**see the coaches waiting for review**, with their profile and documents. Today coach
approval is manual DB editing (a dev-only `coach_review:approve`/`:reject` rake stand-in
from M17); M33 builds the real foundation — admin accounts, a browser login, and the
review list — that M34 (approve/reject + commission) and the rest of the admin milestones
(M35–M37b) build on.

Scope is the **coach/client business only** (restaurants deferred to Part 3), per the
roadmap re-sequencing dated 2026-11-24.

## Goals (what M33 delivers)

1. **Admin web layer** in the existing Rails app, in a **new `admin` module** beside
   `coach_app`:
   - Server-rendered **ERB views** with a simple shared layout (approach A).
   - **Session-cookie auth** (login/logout), **flash**, and **CSRF** — the browser
     middleware the `api_only` app lacks today — enabled **without breaking** the
     mobile JWT JSON API.
2. **`admins` table + model**: email (unique), `has_secure_password` (bcrypt), name,
   timestamps. A Rails-owned table (new migration on the shared DB).
3. **First admin seeding**: a rake task that creates an admin from `ADMIN_EMAIL` /
   `ADMIN_PASSWORD` env vars; refuses if that email already exists. (No self-signup.)
4. **Login / logout**: `/admin/login` (email + password → session), `/admin/logout`.
   Every `/admin/*` page except login requires a signed-in admin, else redirect to login.
5. **Coach review list** (`/admin/coaches` or `/admin`): coaches in `pending_review`,
   newest submission first, showing name, phone, specialties, and submitted date.
   An empty state when none are waiting.
6. **Coach detail** (`/admin/coaches/:id`, read-only): bio, specialties, years, phone,
   email, review status, and the documents (`profile_photo`, `national_id_front`,
   `national_id_back`, `certificate`) viewable inline — streamed through the existing
   `Documents.download` service with `Cache-Control: no-store` (they include ID photos).

**Done when:** a seeded admin can log in through a browser, see every coach waiting for
review, open one, and view their profile and documents. (No approve/reject yet.)

## Non-goals / anti-goals

- **No write actions on coaches** — approve / reject / request-changes / commission /
  suspend all land in **M34**. M33 is read-only review.
- No restaurants (Part 3), no client management (M37b), no subscriptions/money (M36/M37).
- No admin roles/permissions tiers yet (single admin role); no password reset / email
  flows; no admin self-signup.
- Must **not** change or weaken the mobile coach app's JWT auth or any `coach/*` JSON
  behaviour.

## Constraints

- **Shared Postgres with the Node API.** The `admins` table is new and Rails-owned;
  adding it is a normal migration (the shared-DB guard only blocks *resetting* a
  non-`_test` DB). `schema_format = :sql` / `dump_schema_after_migration = false` —
  the plan handles `structure.sql` carefully on the first Rails-authored table.
- **Session vs API isolation.** Session/cookies/CSRF apply to `admin` controllers only;
  `coach_app` stays token-authed with no session. Admin controllers derive from a new
  `Admin::BaseController < ActionController::Base` (not `ActionController::API`), so the
  app stays `api_only` globally while admin opts back into the view/session stack.
- **Document privacy.** ID/certificate images are sensitive: `no-store`, and only a
  signed-in admin may fetch them via an `/admin` route (never reuse the coach's
  JWT route).
- Arabic-first is the stated product principle (roadmap §2) — see the open decision below.

## Approaches

- **A — Server-rendered Rails (chosen).** ERB views + session cookies + flash in a new
  `admin` module; admin controllers use `ActionController::Base`. Simplest, fastest, one
  codebase, and carries the custom M34–37 workflows (approval mirroring Node's rules,
  commission snapshots, review moderation) directly.
- **B — Rails admin gem (Avo/ActiveAdmin/Administrate).** Fast CRUD scaffolding, but it
  auto-CRUDs ActiveRecord models and fights the custom business rules and the Node-owned
  shared schema; rejected.
- **C — Rails JSON admin API + React SPA.** Most UI flexibility but a second build/deploy
  pipeline, token auth and CORS — overkill for an internal tool; rejected.

## Decided (the how)

- New module `app/controllers/admin/*`, `app/views/admin/*`, routes under
  `scope path: "admin", module: "admin"` (named routes, not the API 404 catch-all).
- `Admin::BaseController < ActionController::Base` with `protect_from_forgery`, a
  `require_admin` before_action reading `session[:admin_id]`, and a `current_admin` helper.
- Enable cookies/session/flash middleware for the app (Rails lets an `api_only` app add
  these back); verify the JSON API is unaffected (no session written for `coach/*`).
- `Admin` model with `has_secure_password`; `bcrypt` gem added.
- Views: a minimal shared layout (header with the signed-in admin + logout), the login
  form, the coach list, and the coach detail. Plain CSS, no JS framework.
- Reuse `CoachApp`'s coach/document reading where it fits, but expose document bytes only
  through an `admin`-authed action.

## Language (decided 2026-11-24)

- **English-only.** The admin is an internal CoachNa-team tool; no i18n or RTL on admin
  screens. The roadmap's "Arabic first" principle applies to the partner/customer
  products, not this panel. (Confirmed by the product owner.)

## Left to the builder

- Exact ERB markup and CSS; list pagination only if the pending set is large (unlikely).
- Session timeout / "remember me" (default: session cookie, no remember-me).
- Where the admin layout/styles live; naming of the list vs dashboard root.
