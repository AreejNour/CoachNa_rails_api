# M33 — Admin panel: team login + coach review list — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (native). Steps use `- [ ]`.

**Goal:** A seeded admin can log in through a browser and see every coach waiting for review, with their profile and documents (read-only).

**Architecture:** A new server-rendered `admin` module in the existing Rails app (approach A). The globally `api_only` app gets cookies/session/flash middleware added back; admin controllers inherit `ActionController::Base` (views + CSRF + session), while `coach_app` stays token-authed `ActionController::API`. A new Rails-owned `admins` table backs session-cookie login.

**Tech Stack:** Rails 8 (minitest), ERB views, `bcrypt`/`has_secure_password`, shared Postgres.

**Spec:** `docs/superpowers/specs/2026-11-24-m33-admin-review-list-design.md`

## Global Constraints

- **English-only** admin UI — no i18n/RTL.
- **Shared Postgres:** the only schema change is the new `admins` table (one migration); do not touch Node-owned tables. Tests use the resettable `*_test` DB.
- **Auth isolation:** session/cookies/CSRF apply to `admin` controllers only; the mobile `coach/*` JWT JSON API must be unchanged (full suite stays green).
- **Document privacy:** coach documents (ID/certificate images) are served only to a signed-in admin, with `Cache-Control: no-store`.
- Leave changes **uncommitted** (project rule); the "Commit" steps stage only — do not `git commit`/`push` unless the user asks.
- M33 is **read-only**: no approve/reject/commission/suspend (those are M34).

## Review Focus

- **Unauthenticated access to any `/admin` page** → redirect to `/admin/login`, no content leaked. Tests in Tasks 3, 4, 5.
- **Wrong email/password** → login re-renders with an error and sets no session. Test in Task 3.
- **Non-`pending_review` coaches** (approved/incomplete/rejected) must not appear in the review list. Test in Task 4.
- **Document fetch** must send `Cache-Control: no-store` and only for a signed-in admin. Test in Task 5.
- **Mobile JWT API unaffected** by the added session middleware → the existing suite stays green. Verified at each task's full-suite run.

---

### Task 1: `admins` table + `Admin` model

**Files:**
- Create: `db/migrate/<ts>_create_admins.rb`
- Create: `app/models/admin.rb`
- Add `gem "bcrypt"` to `Gemfile`
- Test: `test/models/admin_test.rb`

**Interfaces:**
- Produces: `Admin` with `email:string` (unique, downcased), `password_digest`, `name:string`, timestamps; `has_secure_password`; `Admin.find_by(email:)` + `admin.authenticate(password)`.

- [ ] **Step 1:** Add `gem "bcrypt"`, run `bundle install`.
- [ ] **Step 2: Write failing tests** in `admin_test.rb`: a saved admin `authenticate`s the right password and rejects a wrong one; email is required and unique (case-insensitive — `"A@B.co"` collides with `"a@b.co"`); `password_digest` is not the plaintext.
- [ ] **Step 3: Run** `bin/rails test test/models/admin_test.rb` — Expected: FAIL (no `admins` table / model).
- [ ] **Step 4:** Create the migration (`email` citext-or-downcased unique index, `password_digest`, `name`, timestamps) and `Admin` model with `has_secure_password`, `validates :email, presence: true, uniqueness: { case_sensitive: false }`, and a `before_save` to downcase email. Run `bin/rails db:migrate` and confirm **only** `admins` was created.
- [ ] **Step 5: Run** the test — Expected: PASS.
- [ ] **Step 6: Commit** (stage only): `git add Gemfile Gemfile.lock db/ app/models/admin.rb test/models/admin_test.rb`

---

### Task 2: First-admin seeding rake task

**Files:**
- Create: `lib/tasks/admin.rake`
- Test: `test/lib/tasks/admin_rake_test.rb`

**Interfaces:**
- Consumes: `Admin` (Task 1).
- Produces: rake task `admin:create` — reads `ENV["ADMIN_EMAIL"]`/`ENV["ADMIN_PASSWORD"]`, creates an admin, aborts if the email already exists or an env var is missing.

- [ ] **Step 1: Write failing tests:** invoking the task with env set creates one `Admin` with that email; invoking again with the same email aborts and creates no duplicate; a missing env var aborts.
- [ ] **Step 2: Run** `bin/rails test test/lib/tasks/admin_rake_test.rb` — Expected: FAIL.
- [ ] **Step 3:** Implement `admin:create` (load `:environment`; `abort` with a message when env missing or `Admin.exists?(email:)`; else `Admin.create!`).
- [ ] **Step 4: Run** the test — Expected: PASS.
- [ ] **Step 5: Commit** (stage only).

---

### Task 3: Admin web layer + login/logout

**Files:**
- Modify: `config/application.rb` (add cookies/session/flash middleware)
- Create: `app/controllers/admin/base_controller.rb`, `app/controllers/admin/sessions_controller.rb`
- Create: `app/views/layouts/admin.html.erb`, `app/views/admin/sessions/new.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/admin/sessions_controller_test.rb`

**Interfaces:**
- Consumes: `Admin` (Task 1).
- Produces:
  - `Admin::BaseController < ActionController::Base` — `layout "admin"`, `protect_from_forgery with: :exception`, `before_action :require_admin`, `helper_method :current_admin`; `require_admin` redirects to `admin_login_path` unless `session[:admin_id]` resolves an `Admin`.
  - `Admin::SessionsController` — `new` (login form, skips `require_admin`), `create` (sets `session[:admin_id]` on success → redirect `admin_root_path`; re-renders `new` with a flash error otherwise), `destroy` (resets session → redirect login).
  - Routes under `scope path: "admin", module: "admin", as: "admin"`: `login` (get `sessions#new`, post `sessions#create`), `logout` (delete `sessions#destroy`), `root` (get `coaches#index`).

- [ ] **Step 1: Write failing integration tests** in `sessions_controller_test.rb`: `GET /admin/login` → 200; `POST /admin/login` with a seeded admin's right creds → redirect to `/admin` and `session[:admin_id]` set; wrong password → 200 re-render, no session; `DELETE /admin/logout` → redirect to login, session cleared; `GET /admin` without login → redirect to `/admin/login`.
- [ ] **Step 2: Run** `bin/rails test test/controllers/admin/sessions_controller_test.rb` — Expected: FAIL (routes/controllers absent).
- [ ] **Step 3:** Add the three middleware lines (`ActionDispatch::Cookies`, `ActionDispatch::Session::CookieStore` key `_coachna_admin_session`, `ActionDispatch::Flash`) in `config/application.rb`; add the routes; implement `Admin::BaseController`, `Admin::SessionsController`, the `admin` layout and login view. Also create a **minimal `Admin::CoachesController < Admin::BaseController` with `def index` rendering a placeholder** (so the `admin_root_path` route resolves and the gate test can run) — Task 4 replaces it with the real list.
- [ ] **Step 4: Run** the test — Expected: PASS. Then run the **full suite** `bin/rails test` — Expected: green (mobile JWT API unaffected).
- [ ] **Step 5: Commit** (stage only).

---

### Task 4: Coach review list

**Files:**
- Modify: `app/controllers/admin/coaches_controller.rb` (real `index`, replacing the Task 3 placeholder)
- Create: `app/views/admin/coaches/index.html.erb`
- Modify: `config/routes.rb` (add the `coaches/:id` show route, named `coach`)
- Test: `test/controllers/admin/coaches_controller_test.rb`

**Interfaces:**
- Consumes: `Admin::BaseController` (Task 3); `Coach` (`status`, `full_name`, `phone`, `specialties`, `profile_submitted_at`).
- Produces: `Admin::CoachesController#index` — `@coaches = Coach.where(status: "pending_review").order(profile_submitted_at: :desc)`; links each to `admin_coach_path(coach)`. Adds the named `coach` route (`coaches/:id`) so the link helper resolves; the `show` action itself is implemented in Task 5.

- [ ] **Step 1: Write failing tests** (sign in a seeded admin in `setup`): index lists a `pending_review` coach's name and **excludes** an `approved` and an `incomplete` coach; renders an empty-state line when none are pending; `GET /admin/coaches` without login redirects to `/admin/login`.
- [ ] **Step 2: Run** the test — Expected: FAIL.
- [ ] **Step 3:** Implement `index` + the ERB list (name, phone, specialties, submitted date) with an empty state.
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (stage only).

---

### Task 5: Coach detail + document viewing

**Files:**
- Modify: `app/controllers/admin/coaches_controller.rb` (`show`, `document`)
- Create: `app/views/admin/coaches/show.html.erb`
- Modify: `config/routes.rb` (add `coaches/:id/documents/:document_id`, named `coach_document`; the `coaches/:id` show route was added in Task 4)
- Test: `test/controllers/admin/coaches_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `CoachApp::Documents.download(document)` → `{ url: } | { bytes: }`; `coach.coach_documents` (with `type`, `mime_type`).
- Produces: `#show` — `@coach = Coach.find(params[:id])`, lists its `coach_documents`; `#document` — finds the coach's document by `params[:document_id]`, streams via `Documents.download` with `response.headers["Cache-Control"] = "no-store"` (redirect when `:url`, else `send_data bytes, type:, disposition: "inline"`).

- [ ] **Step 1: Write failing tests:** signed-in admin `GET /admin/coaches/:id` shows the coach's bio/specialties and a link per document; `GET /admin/coaches/:id/documents/:document_id` returns the bytes (stub `Documents.download` to `{ bytes: "x", }`) with `Cache-Control: no-store`; both redirect to login when unauthenticated.
- [ ] **Step 2: Run** the test — Expected: FAIL.
- [ ] **Step 3:** Add the routes; implement `show` + `document` (reuse `CoachApp::Documents.download`; scope the document lookup to the coach) and the detail view.
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (stage only).
