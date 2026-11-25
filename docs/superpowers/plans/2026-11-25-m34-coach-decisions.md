# M34 — Admin coach decisions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the admin coach pages, an admin can approve (with commission), request changes, reject, suspend, reactivate, and deactivate a coach — each guarded by status, notifying the coach, and recorded in an audit trail.

**Architecture:** A new Rails-owned `coach_status_changes` audit table and an `Admin::CoachDecision` service hold the six-action state machine (reusing the existing `CoachApp::CoachEvents` push/email path). Thin POST actions on the existing `Admin::CoachesController` call the service; the coach detail view shows only the actions valid for the current status. The dev-only `DevCoachReview` stand-in is retired.

**Tech Stack:** Rails 8 (minitest), ERB views, shared Postgres with `schema_format = :sql` (no migrations — Rails-owned tables are hand-added to `db/structure.sql`, matching the M33 `admins` table), `CoachApp::Outbox` for push/email.

**Spec:** `docs/superpowers/specs/2026-11-25-m34-coach-decisions-design.md`

## Global Constraints

- **English-only admin UI.** Coach-facing push/email is **bilingual (ar + en)**, matching existing `CoachApp::CoachEvents::PUSH` entries.
- **No new column on the Node-owned `coaches` table.** The only schema change is the Rails-owned `coach_status_changes` table, hand-added to `db/structure.sql` with the `-- Rails-owned` annotation (exactly like `admins`), and applied as raw SQL to the dev and test databases. Do not add `db/migrate`.
- **Decisions are atomic:** the coach update, the `coach_status_changes` row, and the push/email enqueue commit together in one `Coach.transaction` or not at all.
- Coach field writes stay within the columns the app already owns: `status`, `commission_percent`, `rejection_reason`, `reviewed_at`.
- **Leave changes uncommitted** (project rule — do not `git commit`/`push`); the "Commit" steps **stage only**.
- Admin model is `AdminUser` (table `admins`); the session accessor is `current_admin` (returns an `AdminUser`).

## State machine (authoritative)

| Action | From | To | Required input | Email template | Push event |
|---|---|---|---|---|---|
| `approve!` | `pending_review` | `approved` | `commission` (0–100) | `coach_application_approved` | `approved` |
| `request_changes!` | `pending_review` | `incomplete` | `reason` | `coach_application_needs_changes` | `needs_changes` |
| `reject!` | `pending_review` | `rejected` | `reason` | `coach_application_rejected` | `rejected` |
| `suspend!` | `approved` | `suspended` | `reason` | `coach_suspended` | `suspended` |
| `reactivate!` | `suspended` | `approved` | `reason` | `coach_reactivated` | `reactivated` |
| `deactivate!` | `approved`, `suspended` | `deactivated` | `reason` | `coach_deactivated` | `deactivated` |

Coach field writes: **approve** sets `status`, `commission_percent`, `reviewed_at = now`, `rejection_reason = nil`. **request_changes / reject** set `status`, `rejection_reason = reason`, `reviewed_at = now`. **suspend / reactivate / deactivate** set `status` only (reason lives in the audit row + notification).

## Review Focus

- **Invalid transition** (e.g. approving a `suspended` coach, suspending a `pending_review` coach): the service raises and changes nothing; the view never offers it. Tests in Task 3 (service guard per action) and Task 4 (controller flashes the error).
- **Reject is final:** a `rejected` coach can no longer edit or resubmit (`EDITABLE_STATUSES` drops `rejected`); `ReviewStatus.submit!` returns 409. Test in Task 5.
- **Blank reason / out-of-range commission** is refused and nothing changes. Tests in Task 3.
- **Notification enqueue fails** → the whole decision rolls back (no status change, no audit row, no half-sent messages). Test in Task 3.
- **A coach with no email** still gets the push and the audit row; the email is skipped. Test in Task 3.

---

### Task 1: `coach_status_changes` audit table + model

**Files:**
- Modify: `db/structure.sql` (append the table, annotated `-- Rails-owned`, like `admins`)
- Create: `app/models/coach_status_change.rb`
- Modify: `app/models/coach.rb` (add `has_many :coach_status_changes`)
- Test: `test/models/coach_status_change_test.rb`

**Interfaces:**
- Produces: `CoachStatusChange` with `coach_id:uuid`, `admin_id:uuid`, `from_status`, `to_status`, `reason` (nullable), `commission_percent` (nullable), `created_at`; `belongs_to :coach`; `belongs_to :admin_user, foreign_key: :admin_id`. Later tasks create rows via `coach.coach_status_changes.create!` inside the service.

- [ ] **Step 1: Write failing tests** in `coach_status_change_test.rb`: a row created with a coach, an `AdminUser`, `from_status`/`to_status`, and `reason` persists and reloads; `change.coach` and `change.admin_user` return the associated records; `reason` and `commission_percent` may be nil (an approve-style row). Build the coach with `Coach.create!(full_name: "A", phone: "+201000000001", password_hash: "h", status: "approved")` and the admin with `AdminUser.create!(email: "t@c.app", name: "T", password: "Secret123")`.
- [ ] **Step 2: Run** `bin/rails test test/models/coach_status_change_test.rb` — Expected: FAIL (no table/model).
- [ ] **Step 3:** Add to `db/structure.sql` (placed beside `admins`, same annotation) and apply the identical SQL to the dev and test databases (same way the `admins` table was applied in M33):

```sql
-- Name: coach_status_changes; Type: TABLE; Schema: public; Owner: -
-- Rails-owned (admin panel, M34); not part of the Node API schema.
CREATE TABLE public.coach_status_changes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coach_id uuid NOT NULL,
    admin_id uuid NOT NULL,
    from_status public.coach_status NOT NULL,
    to_status public.coach_status NOT NULL,
    reason text,
    commission_percent numeric(5,2),
    created_at timestamp(6) without time zone NOT NULL
);
ALTER TABLE ONLY public.coach_status_changes
    ADD CONSTRAINT coach_status_changes_pkey PRIMARY KEY (id);
CREATE INDEX index_coach_status_changes_on_coach_id ON public.coach_status_changes USING btree (coach_id);
ALTER TABLE ONLY public.coach_status_changes
    ADD CONSTRAINT coach_status_changes_coach_id_fk FOREIGN KEY (coach_id) REFERENCES public.coaches(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.coach_status_changes
    ADD CONSTRAINT coach_status_changes_admin_id_fk FOREIGN KEY (admin_id) REFERENCES public.admins(id);
```

Then create the `CoachStatusChange` model (set `self.table_name` not needed — name matches; `belongs_to :admin_user, foreign_key: :admin_id`) and add `has_many :coach_status_changes` to `Coach`. Load the schema into the test DB with `bin/rails db:test:prepare`.
- [ ] **Step 4: Run** the test — Expected: PASS.
- [ ] **Step 5: Run** the full suite `bin/rails test` — Expected: green (nothing else touched).
- [ ] **Step 6: Commit** (stage only): `git add db/structure.sql app/models/coach_status_change.rb app/models/coach.rb test/models/coach_status_change_test.rb`

---

### Task 2: New coach-event notifications (reject / suspend / reactivate / deactivate)

**Files:**
- Modify: `app/services/coach_app/coach_events.rb` (add four entries to `PUSH`)
- Test: `test/services/coach_app/coach_events_test.rb`

**Interfaces:**
- Consumes: existing `CoachEvents.push_coach!(coach, event)`.
- Produces: `PUSH` gains `:rejected`, `:suspended`, `:reactivated`, `:deactivated`, each a `{ title: {ar,en}, body: {ar,en}, screen: }` hash. Task 3 calls `push_coach!` with these events and `email_coach!` with the matching templates.

Draft copy (English fixed; **Arabic is a draft for the user to confirm** — see handoff):

| event | screen | en title | en body |
|---|---|---|---|
| `rejected` | `coach_status` | "Your application was declined" | "Open the app to see why." |
| `suspended` | `coach_status` | "Your account is suspended" | "Open the app to see why." |
| `reactivated` | `coach_home` | "Your account is active again" | "You can take clients again." |
| `deactivated` | `coach_status` | "Your account was deactivated" | "Open the app to see why." |

Arabic draft: `rejected` تم رفض طلبك / افتح التطبيق لمعرفة السبب؛ `suspended` تم إيقاف حسابك مؤقتًا / افتح التطبيق لمعرفة السبب؛ `reactivated` تم تفعيل حسابك مجددًا / يمكنك استقبال العملاء مرة أخرى؛ `deactivated` تم إلغاء تفعيل حسابك / افتح التطبيق لمعرفة السبب.

- [ ] **Step 1: Write failing tests:** for each of the four events, `CoachEvents.push_coach!(coach, event)` enqueues one push whose `payload["title"]` and `payload["body"]` have non-blank `"ar"` and `"en"`, `payload["data"]["screen"]` equals the table value, and `payload["recipient"]` is `{ "type" => "coach", "id" => coach.id }`. Read the enqueued row via `OutboxMessage.find_by!(kind: "push").payload` (pattern from `test/lib/dev_coach_review_test.rb`).
- [ ] **Step 2: Run** `bin/rails test test/services/coach_app/coach_events_test.rb` — Expected: FAIL (`KeyError` on the missing events).
- [ ] **Step 3:** Add the four entries to `PUSH` with the copy above.
- [ ] **Step 4: Run** the test — Expected: PASS.
- [ ] **Step 5: Commit** (stage only).

---

### Task 3: `Admin::CoachDecision` service (the six actions)

**Files:**
- Create: `app/services/admin/coach_decision.rb`
- Test: `test/services/admin/coach_decision_test.rb`

**Interfaces:**
- Consumes: `Coach`, `AdminUser`, `CoachStatusChange` (Task 1), `CoachApp::CoachEvents` (Task 2), `CoachApp::Outbox`.
- Produces: `Admin::CoachDecision` module with six methods, each taking keyword args and raising `Admin::CoachDecision::Error` on an invalid transition or bad input:
  - `approve!(coach:, admin:, commission:)`
  - `request_changes!(coach:, admin:, reason:)`
  - `reject!(coach:, admin:, reason:)`
  - `suspend!(coach:, admin:, reason:)`
  - `reactivate!(coach:, admin:, reason:)`
  - `deactivate!(coach:, admin:, reason:)`

  Each: validates input (commission is a number 0–100; reason non-blank), checks the coach's current status is an allowed source for the action (else `Error` naming the current status), then in one `Coach.transaction`: updates the coach's fields (per the state-machine table), creates a `CoachStatusChange` (`admin_id: admin.id`, `from_status`, `to_status`, `reason`, `commission_percent`), and enqueues the push (`CoachEvents.push_coach!`) and email (`CoachEvents.email_coach!`, with `reason:` where the action carries one). Returns the reloaded coach.

- [ ] **Step 1: Write failing tests** in `coach_decision_test.rb` (setup: an `AdminUser` and a `Coach` in the relevant source status; use `swap_method` and `OutboxMessage` as in `dev_coach_review_test.rb`):
  - **Happy path per action:** from the correct source status, the coach lands in the target status with the right field writes (e.g. `approve!` sets `commission_percent` and clears `rejection_reason`; `request_changes!`/`reject!` set `rejection_reason`; `suspend!`/`reactivate!`/`deactivate!` leave `rejection_reason` untouched), and one `CoachStatusChange` row exists with `from_status`, `to_status`, `admin_id`, and (for approve) `commission_percent`.
  - **Notifications:** each action enqueues the matching push event and, when `coach.email` is present, the matching email template (and `reason` in the email data for the actions that carry one).
  - **No email:** a coach without an email still gets the push and the audit row; `OutboxMessage.where(kind: "email").count == 0`.
  - **Invalid transition:** for each action, a coach in every non-source status raises `Error` whose message includes the current status, and nothing changes (status unchanged, no audit row, no outbox rows). (Mirror the `%w[...].each` style from `dev_coach_review_test.rb`.)
  - **Bad input:** `approve!` with commission in `["-1", "101", "abc", "", nil]` raises `Error`; `reject!`/`request_changes!`/`suspend!`/`reactivate!`/`deactivate!` with reason in `[nil, "", "   "]` raises `Error`; nothing changes.
  - **Rollback:** when the second `Outbox.enqueue_and_publish_after_commit!` raises, the status stays at the source, no `CoachStatusChange` row is written, and `OutboxMessage.count == 0` (mirror the rollback test in `dev_coach_review_test.rb`).
- [ ] **Step 2: Run** `bin/rails test test/services/admin/coach_decision_test.rb` — Expected: FAIL (service absent).
- [ ] **Step 3:** Implement `Admin::CoachDecision` with a small internal `transition!(coach, admin, from:, to:, event:, email:, reason: nil, commission: nil, coach_attrs:)` helper that enforces the guard and does the transactional update + audit row + notifications; the six public methods validate their own input and delegate to it.
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (stage only).

---

### Task 4: Controller actions, routes, and the decision panel

**Files:**
- Modify: `config/routes.rb` (six POST member routes in the `admin` scope)
- Modify: `app/controllers/admin/coaches_controller.rb` (six actions)
- Modify: `app/views/admin/coaches/show.html.erb` (decision panel)
- Test: `test/controllers/admin/coaches_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `Admin::CoachDecision` (Task 3); `current_admin` (an `AdminUser`) from `Admin::BaseController`.
- Produces: routes `admin_approve_coach_path`, `admin_request_changes_coach_path`, `admin_reject_coach_path`, `admin_suspend_coach_path`, `admin_reactivate_coach_path`, `admin_deactivate_coach_path` (all POST, `coaches/:id/<action>`); matching controller actions that load `Coach.find(params[:id])`, call the service with `admin: current_admin` and the submitted `reason`/`commission`, rescue `Admin::CoachDecision::Error` → `flash[:alert]`, else `flash[:notice]`, and redirect to `admin_coach_path(coach)`.

- [ ] **Step 1: Write failing integration tests** (sign in via the existing `sign_in` helper; build coaches with the existing `make_coach` helper):
  - `POST admin_approve_coach_path(coach)` with `commission: "15"` on a `pending_review` coach → redirect to `admin_coach_path`, coach reloads `approved` with `commission_percent == 15`.
  - `POST admin_request_changes_coach_path` / `admin_reject_coach_path` with a `reason` → coach `incomplete` / `rejected`, `rejection_reason` set.
  - `POST admin_suspend_coach_path` on an `approved` coach → `suspended`; `admin_reactivate_coach_path` on a `suspended` coach → `approved`; `admin_deactivate_coach_path` on an `approved` coach → `deactivated`.
  - **Invalid transition flashes, no change:** `POST admin_suspend_coach_path` on a `pending_review` coach → redirect, `flash[:alert]` present, status unchanged.
  - **Auth gate:** each action without signing in redirects to `/admin/login` and changes nothing.
  - **View:** `GET admin_coach_path` for a `pending_review` coach shows Approve/Request changes/Reject controls and **not** Suspend/Reactivate; for an `approved` coach shows Suspend and Deactivate and **not** Approve.
- [ ] **Step 2: Run** `bin/rails test test/controllers/admin/coaches_controller_test.rb` — Expected: FAIL.
- [ ] **Step 3:** Add the six routes; implement the six actions (a shared private helper that rescues `Admin::CoachDecision::Error`); extend `show.html.erb` with a decision panel that renders only the controls valid for `@coach.status` (reason `textarea` for the reason-carrying actions, a `number` field for commission on approve; terminal actions `reject`/`deactivate` get a confirm prompt). English copy only.
- [ ] **Step 4: Run** the test, then `bin/rails test` — Expected: PASS / green.
- [ ] **Step 5: Commit** (stage only).

---

### Task 5: Retire the dev stand-in; make reject final

**Files:**
- Delete: `lib/dev_coach_review.rb`, `lib/tasks/coach_review.rake`, `test/lib/dev_coach_review_test.rb`
- Modify: `app/models/coach.rb` (`EDITABLE_STATUSES` → `%w[incomplete]`)
- Modify: `test/models/coach_test.rb`, `test/controllers/coach_app/documents_controller_test.rb`, `test/controllers/coach_app/profiles_controller_test.rb`, `test/controllers/coach_app/review_controller_test.rb`
- Modify: `docs/docs/docs/temporary-code-to-remove.md` (remove the DevCoachReview entry, ~line 111), and the dev-tool section in the Rails `README` it names

**Interfaces:**
- Consumes: nothing new. This task removes the superseded dev path and tightens the editable-status rule the design decided.

- [ ] **Step 1: Update the model-level test first:** change `test/models/coach_test.rb` ("EDITABLE_STATUSES are incomplete and rejected") to assert `%w[incomplete]`.
- [ ] **Step 2: Run** `bin/rails test test/models/coach_test.rb` — Expected: FAIL (still `incomplete rejected`).
- [ ] **Step 3:** Set `Coach::EDITABLE_STATUSES = %w[incomplete].freeze`.
- [ ] **Step 4: Run** `test/models/coach_test.rb` — Expected: PASS.
- [ ] **Step 5: Update the coach-app tests that assumed a rejected coach stays editable** to reflect that only `incomplete` is now editable, and that a `rejected` coach is blocked:
  - `documents_controller_test.rb:~190` and `profiles_controller_test.rb:~173`: change the `%w[incomplete rejected]` loops to `%w[incomplete]`.
  - `review_controller_test.rb:~145` ("a rejected coach can submit again…"): change the subject to an `incomplete` (request-changes) coach, and add an assertion that a `rejected` coach's submit now fails with 409 (`ReviewStatus.submit!` / the review submit endpoint).
- [ ] **Step 6:** Delete the three dev files; remove the DevCoachReview entry from `docs/docs/docs/temporary-code-to-remove.md` and the dev-tool section from the Rails `README`.
- [ ] **Step 7: Run** the full suite `bin/rails test` — Expected: green (no reference to `DevCoachReview` remains; `grep -rn DevCoachReview` returns nothing).
- [ ] **Step 8: Commit** (stage only).
