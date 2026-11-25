# M34 — Admin panel: coach decisions (approve / request-changes / reject + commission + suspend / reactivate / deactivate) — Design

> Status: awaiting approval. Date: 2026-11-25. Milestone: M34 (second admin milestone, follows M33).

## Intent and why

M33 gave an admin a **read-only** view of coaches waiting for review. M34 makes the
admin coach pages **actionable**: an admin can approve a coach (setting their
commission), send an application back for changes, reject it outright, and later
suspend, reactivate, or deactivate an active coach.

This replaces the development-only stand-in `lib/dev_coach_review.rb` and its
`coach_review:approve/:reject` rake task (flagged in
`docs/temporary-code-to-remove.md`), which was never meant for production. After
M34, coaches are managed entirely from the admin panel.

## Goals

- From the coach **detail** page, an admin can take exactly the decisions valid for
  that coach's current status, each in one confirmed step with the required inputs.
- **Review funnel** (`pending_review`):
  - **Approve** — enter a commission percent (0–100) → status `approved`.
  - **Request changes** — enter a reason → status `incomplete`; the coach can edit and
    resubmit, which returns them to `pending_review`.
  - **Reject** — enter a reason → status `rejected`; **final**, no resubmission.
- **Active-coach lifecycle:**
  - **Suspend** (reason) — `approved → suspended` (temporary, reversible).
  - **Reactivate** (reason) — `suspended → approved`.
  - **Deactivate** (reason) — `approved | suspended → deactivated` (**terminal**).
- Every decision **notifies the coach** (push + email, as the dev tool already does for
  approve/request-changes) and is recorded in a new Rails-owned **audit table** with the
  acting admin, the before/after status, the reason, and any commission.
- The full test suite stays green; the mobile coach JWT API is untouched.

## Non-goals (this milestone)

- **Editing commission after approval.** Commission is set once, at approval. Changing a
  live coach's commission is deferred (keeps M34 small; revisit with M37 coach money).
  *(My call — override if you want it in M34.)*
- **Client accounts** (that's M37b) and **subscriptions/meal-order effects** of
  suspension/deactivation (M36). M34 only changes the coach's own status; it does not
  touch that coach's existing client subscriptions.
- **Un-rejecting / un-deactivating.** `rejected` and `deactivated` are terminal in the
  admin UI.
- **An audit-log viewing screen.** M34 *writes* the audit table; a UI to browse history
  is not built yet (the data is there when we want it).

## Anti-goals (would make this a failure even if it "works")

- Any write to a **Node-owned table** (`coaches`, `coach_documents`, …) beyond the two
  columns the app already owns conceptually (`status`, `commission_percent`,
  `rejection_reason`, `reviewed_at`), and **no** new column on `coaches`.
- A coach landing in a status with **no valid way back** that we didn't intend, or an
  admin triggering an **invalid transition** (e.g. approving a suspended coach) because
  the UI offered it.
- A decision that updates the coach **but fails to notify or fails to audit** (or the
  reverse) — the status change, the notification enqueue, and the audit row must commit
  together or not at all.

## Constraints

- **English-only** admin UI (as M33). Coach-facing **push/email is bilingual (ar + en)**,
  matching the existing `CoachEvents` specs.
- **Shared Postgres.** The only schema change is the new Rails-owned
  `coach_status_changes` table (one migration, same ownership model as the M33 `admins`
  table). Tests use the resettable `*_test` DB.
- Reuse the existing notification path: `CoachApp::CoachEvents.push_coach!` /
  `.email_coach!`, enqueued **inside** the status-change transaction (they publish
  after commit).
- **Leave changes uncommitted** (project rule — [[no-commit-no-push]]); stage only if asked.

## Approaches considered

Where the per-action reason, the acting admin, and the history live:

- **A — Reuse existing `coaches` columns, no history.** Put every reason in
  `rejection_reason`, the time in `reviewed_at`, and don't record the admin. Smallest
  change, but conflates meanings (a suspension reason in a field named "rejection"),
  keeps no history, and can never answer "who suspended this coach and why." Rejected for
  a panel that sets commissions and disables accounts.
- **B — Rails-owned audit table (CHOSEN).** A new greenfield `coach_status_changes` table
  owned by Rails (same pattern as M33 `admins`), one row per decision: coach, acting
  admin, from/to status, reason, commission. Full audit + actor for free; never touches a
  Node table. The coach-facing `rejection_reason` is still written for
  request-changes/reject so the coach app's existing status message is unchanged;
  suspend/deactivate reasons live in the audit row and the notification.
- **C — Add columns to `coaches` via a Node migration.** Rejected: violates the
  no-touch-Node-tables constraint and couples the two repos for no gain over B.

**Chosen: B**, decided 2026-11-25.

## The design (decided)

### State machine (the single source of allowed transitions)

| Action | From | To | Required input | Reversible |
|---|---|---|---|---|
| Approve | `pending_review` | `approved` | commission % (0–100) | — |
| Request changes | `pending_review` | `incomplete` | reason | coach resubmits → `pending_review` |
| Reject | `pending_review` | `rejected` | reason | no (terminal) |
| Suspend | `approved` | `suspended` | reason | via Reactivate |
| Reactivate | `suspended` | `approved` | reason | — |
| Deactivate | `approved`, `suspended` | `deactivated` | reason | no (terminal) |

The detail page shows **only the actions valid for the current status**. The service
re-checks the guard server-side and refuses an invalid transition with a clear message
(defence in depth; the UI should never offer one).

### Coach field writes (on `coaches`, app-owned columns only)

- Approve: `status`, `commission_percent`, `reviewed_at = now`, `rejection_reason = nil`.
- Request changes / Reject: `status`, `rejection_reason = reason`, `reviewed_at = now`
  (keeps the coach app's existing "needs changes" / "declined" message working).
- Suspend / Reactivate / Deactivate: `status` only (reason lives in the audit row +
  notification, not on `coaches`).

### `coach_status_changes` (new, Rails-owned)

Columns: `id`, `coach_id` (uuid, indexed), `admin_id` (fk → `admins`), `from_status`,
`to_status`, `reason` (null for approve), `commission_percent` (null except approve),
`created_at`. One row written inside every decision's transaction. Rails owns it — Node
migrations never see it (register it the same way M33's `admins` table is registered).

### Service object

A new service (e.g. `Admin::CoachDecision` / `CoachReview`) replaces `DevCoachReview`,
exposing one method per action. Each: loads the coach, enforces the guard, and in a single
`Coach.transaction` updates the coach, writes the `coach_status_changes` row (with the
acting admin), and enqueues the push + email. Validates commission (0–100) and
non-blank reasons, raising a typed error the controller turns into a flash.

### Notifications (extend `CoachApp::CoachEvents`)

Existing: `approved`, `needs_changes` push specs; `coach_application_approved`,
`coach_application_needs_changes` email templates — reused for approve and request-changes.

**New push specs** (bilingual ar/en) and **email template names**:
`rejected` → `coach_application_rejected`, `suspended` → `coach_suspended`,
`reactivated` → `coach_reactivated`, `deactivated` → `coach_deactivated`. Reason text is
passed through the existing `email_coach!(…, reason:)` argument.

*Dependency:* the email **renderer** (Node-side mail service that consumes the Outbox)
must have these four new templates. Rails' responsibility ends at enqueuing the correct
template name; if the renderer lacks them, that's a coordinated follow-up on the Node
side, not a blocker for the Rails work or its tests (which assert the enqueued payload).

### Admin UI

On the coach detail page, a decision panel whose buttons match the current status. Each
action that needs input (reason, or commission) submits a small form (reason textarea /
commission number field) via POST; CSRF-protected session forms as in M33. A plain
confirmation guards the terminal actions (reject, deactivate). English copy only.

### Controller + routes

Six POST member actions on `Admin::CoachesController`
(`approve`, `request_changes`, `reject`, `suspend`, `reactivate`, `deactivate`) under the
existing `scope path: "admin", module: "admin", as: "admin"`, each calling the service and
redirecting back to the coach with a flash.

### Removals

Delete `lib/dev_coach_review.rb`, `lib/tasks/coach_review.rake`, and
`test/lib/dev_coach_review_test.rb`; drop their entry from
`docs/temporary-code-to-remove.md` ([[track-temporary-code]]). Drop `rejected` from
`Coach::EDITABLE_STATUSES` (now `%w[incomplete]`) so a rejected coach cannot resubmit —
only request-changes reopens the funnel.

## Left to the builder

- Exact service/class name and file layout (follow the existing `app/services/coach_app`
  and `lib/` conventions).
- The ERB decision-panel markup and minimal styling, consistent with the M33 admin layout.
- Migration details for `coach_status_changes` (fk constraints, index names) and how the
  Rails-owned table is excluded from the Node schema dump, mirroring M33 `admins`.
- **Arabic push copy** for the four new events — draft provided for review; the user
  should confirm the Arabic wording before ship.
```

### Open items for the user to confirm (not blockers to approval)

1. **Commission after approval** stays out of M34 (non-goal above). OK?
2. **Arabic notification copy** for reject/suspend/reactivate/deactivate — I'll draft it;
   you confirm the wording.
