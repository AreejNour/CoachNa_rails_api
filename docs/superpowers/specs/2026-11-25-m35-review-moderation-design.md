# M35 — Admin panel: coach-review moderation (approve / reject pending reviews) — Design

> Status: self-approved (user is AFK and authorized autonomous execution of M35). Date: 2026-11-25. Milestone: M35 (third admin milestone, follows M34).

## Intent and why

Client-written coach reviews are created `pending` and **nothing is published until an admin decides them** (roadmap M9: "nothing is published until Milestone 35"). Today the only thing that moves a review out of `pending` is a **development-only timer** in Node (`DEMO_AUTO_RESPOND` → `scheduleDemoApproval` → `decideReview('approve')`); in production reviews pile up unseen. M35 gives a real admin a **moderation queue** in the Rails admin panel to approve or reject each pending coach review — finally unblocking production review publishing.

## Goals

- A signed-in admin sees a **queue of pending coach reviews** (oldest first), each showing the coach, the client, the star rating, the written body, and the before/after photos.
- From a review's detail page the admin can:
  - **Approve** → review `status = visible`, its photos `status = visible`, `decided_at`/`decided_by` set, and the coach's denormalized rating recomputed so the client's public coach page shows the new stars/count.
  - **Reject** → review `status = rejected`, its photos `status = rejected`, `decided_at`/`decided_by` set, and the **photo files deleted** from shared storage (the client may then write a new review — existing Node behavior, unchanged).
- Only a `pending` review can be decided; a second decision on an already-decided review is refused (no double-count, no double-delete).
- Review **photos are viewable only by a signed-in admin**, served with `Cache-Control: no-store` (same rule as M33 coach documents).
- The full test suite stays green; the Node API, coach app, and client app are unchanged.

## Non-goals (this milestone)

- **Hiding / restoring already-published reviews** (the `hidden`/`hidden_reason`/`hidden_by` path). Deferred — M35 is pending → visible/rejected only. *(User-chosen scope.)*
- **Restaurant reviews** — deferred to Part 3 (restaurant app).
- **Editing or deleting a review's text/rating**, bulk moderation, pagination/search of the queue (add later if the queue grows — YAGNI for v1).
- **Notifying the client** of the decision. Node's `decideReview` sends no notification; M35 keeps parity (the client app surfaces review status on its own). No push/email here.
- **Removing or changing any Node code**, including the dev `DEMO_AUTO_RESPOND` auto-approve (it is config-gated and off in production; it stays).

## Anti-goals (would make this a failure even if it "works")

- A rating that **drifts from Node's formula** — the recompute must match `recomputeCoachRating` exactly, or the client page and admin disagree.
- A **double decision** race: two admins (or an admin + the dev timer) both deciding the same review, double-counting the rating or deleting photos twice. The decision must lock the review row and re-check `pending` inside the transaction.
- Writing any **Node-owned column beyond the moderation fields the schema already defines** (`coach_reviews.status/decided_at/decided_by`, `review_photos.status`, `coaches.average_rating/review_count`), or adding a column/table/migration.
- **Leaking a pending review photo** to anyone not signed in as an admin, or deleting the **wrong** files on reject.
- A decision that updates the review but **fails to recompute** (approve) or **fails to mark/delete photos** (reject), or the reverse — the row updates, the photo-status updates, and the rating recompute must commit together; file deletion happens after commit and never fails the decision.

## Constraints

- **English-only** admin UI (as M33/M34). No coach/client-facing copy in M35 (no notifications).
- **Shared Postgres; everything M35 touches is Node-owned and already exists** — `coach_reviews` (`status` text default `pending`; `decided_at`, `decided_by uuid`), `review_photos` (`kind` before/after, `storage_key`, `status` text), `coaches.average_rating numeric(2,1)` + `review_count int`. **No schema change, no migration, no new table.** `decided_by` is set to the signed-in `AdminUser` id.
- **Recompute must mirror Node `recomputeCoachRating` exactly** (`coaches_api/src/coaches/coaches.service.ts`): `avg` and `count` over the coach's `visible` reviews; `average_rating = round(avg*10)/10` (one decimal) and `null` when there are zero visible; `review_count = visibleCount`.
- **Decision mechanics mirror Node `decideReview`** (`coaches_api/src/reviews/decide-review.ts`): lock the review row `FOR UPDATE`; require `pending` (else refuse); set review + its photos to the new status; on **approve** lock the coach row then recompute; on **reject** collect the photos' `storage_key`s and **delete the files after commit** via `Storage.current.delete(key)`, rescuing/logging per-file errors so a storage failure never rolls back the decision.
- Reuse the M33/M34 admin stack: `Admin::BaseController` session auth, `current_admin` (an `AdminUser`), CSRF, the `admin` layout. Reuse the existing Rails review models (`CoachReview`, `ReviewPhoto`) and `Storage.current` (built in M23).
- **Branch `feat/m35-review-moderation` off `main`** (M35 depends only on M33's admin auth, already on main; independent of the unmerged M34 branch). Local commits only — no push, no merge (user reviews/merges).

## Approaches considered

Where the moderation decision logic lives:

- **A — Reimplement the decision in Rails (CHOSEN).** A Rails `Admin::ReviewDecision` service mirrors Node's `decideReview`, plus a Rails recompute mirroring `recomputeCoachRating`, plus an admin queue/detail UI. Self-contained admin panel (same pattern as M34), no runtime Rails→Node coupling, `decided_by` = `AdminUser` id. Cost: the recompute and photo rules are duplicated in Ruby — contained by tests that pin them to Node's formula.
- **B — Rails UI calls a new Node moderation endpoint.** One source of truth, but adds runtime Rails→Node coupling, a service-to-service auth channel, and a Node admin-identity concept for `decided_by`. Breaks the self-contained-Rails-admin model. Rejected.
- **C — Move moderation fully to Rails and delete Node's decide path.** `decideReview` also backs the dev auto-approve and is the real M13 logic, not a dev-only stand-in; deleting it forces Node changes against the greenfield-Rails-admin approach. Rejected.

**Chosen: A**, decided 2026-11-25.

## The design (decided)

### Moderation queue — `Admin::ReviewsController#index`
`@reviews = CoachReview.where(status: "pending").order(created_at: :asc)` (FIFO). The list shows, per review: coach name, client (name or id), rating, a body excerpt, submitted date, and a photo count; each links to the detail page. Empty state when none are pending.

### Review detail — `#show`
`@review = CoachReview.find(params[:id])` with its coach, client, full body, rating, and its `review_photos` (before/after). Photos render as admin-only `<img>`/links pointing at `#photo`. Shows **Approve** and **Reject** buttons only when `@review.status == "pending"` (otherwise a read-only "already <status>" line). Reject is the destructive action and gets a dependency-free confirm (`onsubmit="return confirm(…)"`, per the M34 fix — the admin panel ships no JS).

### Photo serving — `#photo`
Admin-only (behind `require_admin`), `Cache-Control: no-store`. Finds the photo scoped to the review (`@review.review_photos.find(params[:photo_id])`) and streams it via `Storage.current` — reuse the M23 review-photo read path and the M33 document-serving pattern (redirect when the storage driver yields a URL, else `send_data bytes, type:, disposition: "inline"`).

### Decision service — `Admin::ReviewDecision`
Module of class methods (house style), error class `Admin::ReviewDecision::Error < StandardError`:
- `approve!(review:, admin:)` and `reject!(review:, admin:)`.
- Each, in one `CoachReview.transaction`:
  1. Re-load the review **with a row lock** (`CoachReview.lock.find(review.id)` / `.lock!`) and refuse with `Error("already decided")` unless `status == "pending"` (defence against a double decision / the dev timer).
  2. Set the review `status` (`visible`/`rejected`), `decided_at = Time.current`, `decided_by = admin.id`.
  3. Set all the review's `review_photos` `status` to the same value.
  4. **Approve:** lock the coach row, then recompute the coach's rating (below). **Reject:** collect the photos' `storage_key`s.
  5. **Reject only, after commit:** `Storage.current.delete(key)` for each collected key, rescuing and logging per-file errors (never re-raise). Approve deletes nothing.

### Rating recompute — `Admin::CoachRating.recompute(coach_id)` (or a private service method)
Mirrors Node exactly: over the coach's `visible` `coach_reviews`, compute `AVG(rating)` and `COUNT(*)`; write `coaches.average_rating = count > 0 ? round(avg*10)/10.0 : nil` and `coaches.review_count = count`. Runs inside the approve transaction, after the coach-row lock. Pinned to Node's formula by tests.

### Controller + routes
`Admin::ReviewsController` actions `index`, `show`, `photo`, `approve` (POST), `reject` (POST), under the existing `scope path: "admin", module: "admin", as: "admin"` block. Approve/reject load the review, call the service with `admin: current_admin`, set a per-action `flash[:notice]` ("Review approved." / "Review rejected."), rescue `Admin::ReviewDecision::Error` → `flash[:alert]`, and redirect to the review (or the queue). Thin controller; logic in the service.

### Admin nav
Add a link to the moderation queue (`admin_reviews_path`) from the admin layout/nav so it is reachable alongside the coach list.

## Left to the builder

- Exact class/file names and layout, following `app/services/coach_app/*`, the M34 `Admin::CoachDecision` service, and the M23 review-reading services/serializers for the photo-streaming path.
- Whether the recompute lives in its own `Admin::CoachRating` module or as a private method of `Admin::ReviewDecision` — either is fine; keep it independently testable and pin it to Node's `round(avg*10)/10`, null-at-zero behavior.
- The exact SQL for the aggregate (mirror Node: `AVG(rating)`, `COUNT(id)` where `status = 'visible'`) and the Ruby rounding that matches `Math.round(avg*10)/10`.
- ERB markup for the queue, the detail panel, and photo thumbnails, consistent with the M33/M34 admin views.
- The queue's client display (name vs id) — show whatever the `Client` model already exposes; do not add a query the admin doesn't need.
- Row-lock idiom (`lock!` / `with_lock` / `lock.find`) and the coach-row lock on approve, matching how M34/existing Rails code locks rows.
```
