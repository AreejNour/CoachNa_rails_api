# M35 — Admin coach-review moderation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An admin can work a queue of pending coach reviews and approve (publish + recompute the coach's rating) or reject (delete photos) each one, from the Rails admin panel.

**Architecture:** A Rails `Admin::ReviewDecision` service mirrors Node's `decideReview`, backed by an `Admin::CoachRating` recompute that mirrors `recomputeCoachRating`; thin `Admin::ReviewsController` actions drive a server-rendered queue + detail UI. No Node code and no schema change — all touched columns (`coach_reviews.status/decided_at/decided_by`, `review_photos.status`, `coaches.average_rating/review_count`) already exist and are Node-owned.

**Tech Stack:** Rails 8 (minitest), ERB views, shared Postgres, `Storage.current` (M23), M33/M34 admin session stack.

**Spec:** `docs/superpowers/specs/2026-11-25-m35-review-moderation-design.md`

## Global Constraints

- **English-only** admin UI. No coach/client notifications (M35 sends none — parity with Node `decideReview`).
- **No schema change, no migration, no new table.** Writes stay within the existing Node-owned columns listed above. `decided_by` = the signed-in `AdminUser` id.
- **Recompute mirrors Node `recomputeCoachRating` exactly:** over the coach's `visible` reviews, `average_rating = count > 0 ? round(avg*10)/10 : nil`, `review_count = count`.
- **Decision mirrors Node `decideReview`:** lock the review row, require `status == "pending"` (else refuse); set the review AND its `review_photos` to the new status; approve → lock coach row + recompute; reject → delete the photos' files via `Storage.current.delete` **after commit**, per-file errors logged and never fatal.
- Reuse `Admin::BaseController` (session auth, `current_admin` → `AdminUser`, CSRF, `admin` layout), models `CoachReview`/`ReviewPhoto`, and `Storage.current` (`download_url(key, ttl)` / `read(key)` / `delete(key)`).
- Admin panel ships **no JavaScript**: the destructive **Reject** confirm must be a native `onsubmit="return confirm(…)"` (per the M34 fix), not `data-confirm`.
- **Leave uncommitted?** No — this runs on branch `feat/m35-review-moderation` (off `main`); each task makes a **local commit**. No push, no merge (the user reviews/merges).

## Review Focus

- **Double / already-decided decision:** approving or rejecting a review that is already `visible`/`rejected` is refused, and the rating is never double-counted — the decision locks the row and re-checks `pending` inside the transaction. Tests in Task 2.
- **Rating drift from Node:** the recompute must count only `visible` reviews, round `avg*10` to one decimal, and write `nil`/`0` when none are visible — not include pending/rejected/hidden. Tests in Task 1.
- **Reject deletes exactly the right files, non-fatally:** only the rejected review's photo `storage_key`s are deleted, after commit, and a storage error does not roll back or raise. Tests in Task 2.
- **Pending photo privacy:** `#photo` is reachable only by a signed-in admin and sends `Cache-Control: no-store`. Test in Task 3.
- **Approve publishes correctly:** approve sets the review + its photos `visible` and recomputes the coach's denormalized rating, all atomically. Tests in Task 2.

---

### Task 1: `Admin::CoachRating.recompute` (mirror Node)

**Files:**
- Create: `app/services/admin/coach_rating.rb`
- Test: `test/services/admin/coach_rating_test.rb`

**Interfaces:**
- Produces: `Admin::CoachRating.recompute(coach_id)` — over `CoachReview.where(coach_id:, status: "visible")` compute `AVG(rating)` and `COUNT(*)`; update that coach's `average_rating = count.positive? ? (avg.to_f * 10).round / 10.0 : nil` and `review_count = count`. Returns nothing relied upon. Consumed by `Admin::ReviewDecision` (Task 2).

- [ ] **Step 1: Write failing tests** (plain `ActiveSupport::TestCase`): build a coach (`Coach.create!(full_name: "A", phone: "+201000000070", password_hash: "h", status: "approved")`) and a client (reuse the existing test factory/fixture for `Client`, or create one the way other review tests do). Cases:
  - three `visible` reviews ratings 5,4,4 → `average_rating == 4.3`, `review_count == 3`;
  - ratings 5,4 → `4.5` (rounding boundary);
  - a coach with only `pending`/`rejected`/`hidden` reviews (and/or none) → `average_rating.nil?`, `review_count == 0`;
  - a `visible` review for ANOTHER coach is excluded from this coach's aggregate.
- [ ] **Step 2: Run** `bin/rails test test/services/admin/coach_rating_test.rb` — Expected: FAIL (no service).
- [ ] **Step 3:** Implement `recompute` using a single aggregate query (`CoachReview.where(...).pick(Arel.sql("AVG(rating)"), Arel.sql("COUNT(*)"))` or equivalent), then `Coach.where(id: coach_id).update_all(...)` or load + `update!`. Match Node's `round(avg*10)/10` and null-at-zero exactly.
- [ ] **Step 4: Run** the test — Expected: PASS. Then `bin/rails test` — Expected: green.
- [ ] **Step 5: Commit** (local): `git add app/services/admin/coach_rating.rb test/services/admin/coach_rating_test.rb`

---

### Task 2: `Admin::ReviewDecision` service (approve! / reject!)

**Files:**
- Create: `app/services/admin/review_decision.rb`
- Test: `test/services/admin/review_decision_test.rb`

**Interfaces:**
- Consumes: `CoachReview`, `ReviewPhoto`, `AdminUser`, `Admin::CoachRating` (Task 1), `Storage.current`.
- Produces: `Admin::ReviewDecision` module with `approve!(review:, admin:)` and `reject!(review:, admin:)`, raising `Admin::ReviewDecision::Error` when the review is not `pending`. Each runs in one `CoachReview.transaction`:
  1. Re-load the review with a row lock (`CoachReview.lock.find(review.id)`); unless its `status == "pending"`, raise `Error` (message includes the current status). 
  2. Update the review: `status` (`"visible"`/`"rejected"`), `decided_at: Time.current`, `decided_by: admin.id`.
  3. Update all of its `review_photos` `status` to the same value.
  4. **approve!:** lock the coach row (`Coach.lock.find(review.coach_id)`), then `Admin::CoachRating.recompute(review.coach_id)`. **reject!:** collect the photos' `storage_key`s.
  5. **reject! only, after the transaction commits:** `Storage.current.delete(key)` for each key, each wrapped so an error is logged (`Rails.logger`) and never re-raised. approve! deletes nothing.

- [ ] **Step 1: Write failing tests** (pattern from `test/services/admin/coach_decision_test.rb` and `coaches_api/src/reviews/decide-review.test.ts`; use `swap_method` to stub `Storage.current`): seed a coach, client, a `pending` review with two `review_photos`.
  - **approve!:** review → `visible`, both photos → `visible`, `decided_at` set, `decided_by == admin.id`; the coach's `average_rating`/`review_count` reflect the now-visible review (recompute ran); `Storage.current.delete` is NOT called.
  - **reject!:** review → `rejected`, both photos → `rejected`, `decided_*` set; `Storage.current.delete` called once per photo `storage_key`; the coach's rating is unchanged (no recompute on reject).
  - **already decided:** a `visible` (and a `rejected`) review → `approve!`/`reject!` raises `Error` with the status in the message; nothing changes (status, photos, rating, no delete calls).
  - **no photos:** `reject!` on a photoless pending review succeeds, zero delete calls.
  - **storage error non-fatal:** stub `Storage.current.delete` to raise; `reject!` still commits (review `rejected`, decided set) and does not re-raise.
  - **rollback:** stub `Admin::CoachRating.recompute` to raise inside `approve!`; review stays `pending`, photos unchanged, rating unchanged.
- [ ] **Step 2: Run** `bin/rails test test/services/admin/review_decision_test.rb` — Expected: FAIL.
- [ ] **Step 3:** Implement the module with a private helper shared by the two actions (lock + guard + status writes + photo-status write), the approve/reject branches, and the after-commit deletion (collect keys inside the transaction, delete after it returns).
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (local).

---

### Task 3: Moderation queue + detail + photo serving (read side)

**Files:**
- Create: `app/controllers/admin/reviews_controller.rb` (`index`, `show`, `photo`)
- Create: `app/views/admin/reviews/index.html.erb`, `app/views/admin/reviews/show.html.erb`
- Modify: `config/routes.rb` (three GET routes in the `admin` scope)
- Modify: `app/views/layouts/admin.html.erb` (nav link to the queue)
- Test: `test/controllers/admin/reviews_controller_test.rb`

**Interfaces:**
- Consumes: `Admin::BaseController` (`current_admin`, `require_admin`), `CoachReview`/`ReviewPhoto`, `Storage.current`.
- Produces:
  - Routes (inside `scope path: "admin", module: "admin", as: "admin"`): `get "reviews" … as: :reviews` (→ `reviews#index`), `get "reviews/:id" … as: :review` (→ `reviews#show`), `get "reviews/:id/photos/:photo_id" … as: :review_photo` (→ `reviews#photo`). Helpers: `admin_reviews_path`, `admin_review_path`, `admin_review_photo_path`.
  - `#index` — `@reviews = CoachReview.where(status: "pending").order(created_at: :asc)`.
  - `#show` — `@review = CoachReview.find(params[:id])`; lists `@review.review_photos`.
  - `#photo` — `photo = CoachReview.find(params[:id]).review_photos.find(params[:photo_id])`; set `response.headers["Cache-Control"] = "no-store"`; build the download from `Storage.current` (mirror `CoachApp::Reviews.photo`'s shape but WITHOUT the `visible` filter — admins view pending photos): `url = Storage.current.download_url(photo.storage_key, 300)`; redirect to `url` when present (`allow_other_host: true`), else `send_data Storage.current.read(photo.storage_key), type: <mime-from-ext>, disposition: "inline"`. Rescue `Storage::NotFound`/`Storage::InvalidKey` → `head :not_found`.

- [ ] **Step 1: Write failing integration tests** (sign in with an `AdminUser` as in `test/controllers/admin/coaches_controller_test.rb`; build a coach, client, and reviews): 
  - index lists a `pending` review (coach name, rating, body) and **excludes** a `visible` and a `rejected` review; empty-state line when none pending; unauthenticated `GET admin_reviews_path` redirects to `/admin/login`.
  - show renders the review's rating/body and a photo link (`admin_review_photo_path`) per photo; unauthenticated redirects to login.
  - photo returns the bytes with `Cache-Control: no-store` for a signed-in admin (stub `Storage.current` so `download_url` is nil and `read` returns `"IMG"`); unauthenticated redirects to login.
- [ ] **Step 2: Run** `bin/rails test test/controllers/admin/reviews_controller_test.rb` — Expected: FAIL.
- [ ] **Step 3:** Add the routes, controller, the two views (queue table with empty state; detail with photo thumbnails/links), and a nav link to `admin_reviews_path` in the admin layout.
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (local).

---

### Task 4: Approve / reject actions (write side)

**Files:**
- Modify: `config/routes.rb` (two POST routes in the `admin` scope)
- Modify: `app/controllers/admin/reviews_controller.rb` (`approve`, `reject`)
- Modify: `app/views/admin/reviews/show.html.erb` (Approve + Reject controls)
- Test: `test/controllers/admin/reviews_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `Admin::ReviewDecision` (Task 2); `current_admin`.
- Produces: routes `post "reviews/:id/approve" … as: :approve_review` and `post "reviews/:id/reject" … as: :reject_review` (helpers `admin_approve_review_path`, `admin_reject_review_path`); controller actions that load `CoachReview.find(params[:id])`, call `Admin::ReviewDecision.approve!/reject!(review:, admin: current_admin)`, set a per-action `flash[:notice]` ("Review approved." / "Review rejected."), rescue `Admin::ReviewDecision::Error` → `flash[:alert] = e.message`, and `redirect_to admin_review_path(review)`. Thin — no re-validation.

- [ ] **Step 1: Write failing tests** (extend the Task 3 file): 
  - `POST admin_approve_review_path(review)` on a `pending` review → redirect, review reloads `visible`, the coach's `review_count` incremented (recompute ran), `flash[:notice]`.
  - `POST admin_reject_review_path(review)` on a `pending` review (stub `Storage.current.delete`) → review `rejected`, delete called per photo, `flash[:notice]`.
  - approve/reject on an already-`visible` review → redirect with `flash[:alert]`, status unchanged.
  - each action unauthenticated → redirect to `/admin/login`, nothing changes.
  - **View gating:** `GET admin_review_path` for a `pending` review shows Approve and Reject controls; for a `visible`/`rejected` review shows neither (a read-only "already …" line). The Reject form carries `onsubmit=` with `confirm(` (dependency-free confirm).
- [ ] **Step 2: Run** the test — Expected: FAIL.
- [ ] **Step 3:** Add the two routes; implement `approve`/`reject` (a shared private helper that rescues `Admin::ReviewDecision::Error`); add the Approve (`form_with` POST) and Reject (`form_with` POST with `html: { onsubmit: "return confirm('Reject this review? Its photos will be deleted.')" }`) controls to `show.html.erb`, rendered only when `@review.status == "pending"`.
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (local).
