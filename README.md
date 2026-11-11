# CoachNa Rails API

The backend for the CoachNa coach app, and later the restaurant web app and admin panel. The client app keeps its own backend, [`CoachNa_api`](https://github.com/AreejNour/CoachNa_api) (Node).

Runs on port **3003**. Everything is under a module for each product: coach routes are `/coach/*`, in `CoachApp`.

## Shared database: read this first

Development uses the **same database as the Node API**, and Node's migrations create the tables. Rails owns no tables yet.

Rails' usual setup commands would wipe that database, so `lib/shared_db_guard.rb` makes them refuse to run:

- `db:drop`, `db:purge`, `db:reset`, `db:setup`, `db:prepare`, `db:schema:load`, `db:migrate:reset`, `db:truncate_all`, `db:seed:replant` and `db:test:purge` only run against a database named `*_test`.
- `db:migrate`, `db:migrate:up`, `db:migrate:down`, `db:migrate:redo`, `db:rollback`, `db:forward` and `db:environment:set` follow the same rule, because they'd add Rails' own tables to the shared database even with no migrations to run.
- `db:drop:all` and `db:purge:all` never run, because they reach every environment's database.

Don't remove the guard. How Rails changes tables will be decided when it first needs to.

## Setup

You need Ruby 4.0.9, the PostgreSQL 16 client tools, and the Postgres server and Node migrations from `CoachNa_api`.

```bash
sudo apt install build-essential libpq-dev postgresql-client-16 libyaml-dev libssl-dev zlib1g-dev libffi-dev
sudo snap install ruby --classic --channel=4.0/stable
export PATH="$HOME/.gem/bin:$PATH"

bundle install
cp .env.example .env
RAILS_ENV=test bin/rails db:create db:schema:load
```

In `.env`, keep `LOCAL_STORAGE_DIR` pointing at the **Node API's storage folder**. Node serves coach photos to the client app, so files uploaded here must land where it reads them. Rails refuses to start storing files in development if that folder is missing.

Set `JWT_ACCESS_SECRET` to the **same value as the Node API's**.

## Run and test

```bash
bin/rails server    # http://localhost:3003
bin/rails server -b 0.0.0.0 -p 3003    # reachable from a real phone; -b alone falls back to port 3000
bin/rails test      # uses coacha_rails_test, never the shared database
bin/rubocop
```

Tests run one at a time on purpose: Rails' parallel mode makes extra databases that the guard can't recognise.

## When Node's tables change

`db/structure.sql` is a copy of the shared table structure, used to build the test database. After a Node migration that Rails needs:

```bash
bin/dump-shared-schema
RAILS_ENV=test bin/rails db:schema:load
```

## Approving a coach in development

The admin panel arrives in Milestones 33-34. Until then, use these commands, which refuse to run in production:

```bash
bin/rails coach_review:approve PHONE=+201001234567 COMMISSION=15
bin/rails coach_review:reject PHONE=+201001234567 REASON="Your certificate photo is too blurry to read."
```

## Coach API

Responses are `{ "success": true, "data": ... }` or `{ "success": false, "error": "..." }`.

| Route | Purpose |
|---|---|
| `GET /health` | Health check |
| `GET /coach/auth/countries` | Countries and calling codes |
| `POST /coach/auth/signup/request-otp` | Send a sign-up code |
| `POST /coach/auth/signup/check-otp` | Check a code without using it |
| `POST /coach/auth/signup/verify` | Create the account |
| `POST /coach/auth/login` | Log in |
| `POST /coach/auth/refresh` | Swap a refresh token for a new pair |
| `POST /coach/auth/logout` | Revoke a refresh token |
| `GET /coach/me` | The signed-in coach |
| `PATCH /coach/profile` | Edit profile details |
| `GET /coach/profile/status` | Review status, what's missing, and documents |
| `POST /coach/profile/documents` | Add or replace a document |
| `DELETE /coach/profile/documents/:id` | Remove a document |
| `GET /coach/profile/documents/:id/file` | Read a document |
| `POST /coach/profile/submit` | Submit for review |
| `GET /coach/packages` | List your active packages, newest first |
| `POST /coach/packages` | Create a package |
| `PATCH /coach/packages/:id` | Edit a package |
| `DELETE /coach/packages/:id` | Remove a package (soft delete) |
| `GET /coach/questionnaire` | List your non-archived questions, in order |
| `POST /coach/questionnaire/questions` | Add a question (creates the questionnaire if needed) |
| `PATCH /coach/questionnaire/questions/:id` | Edit a question (not its type) |
| `DELETE /coach/questionnaire/questions/:id` | Remove a question (archive) |
| `GET /coach/clients` | List your subscribers, with which are new |
| `GET /coach/clients/:id` | One client's health profile and questionnaire answers |
| `POST /coach/clients/mark-seen` | Mark the new-client notifications read |
| `GET /coach/notifications/unread-count` | Your unread notification count |

No SMS is sent yet. Codes go to the log and, outside production, come back as `devCode`. See `docs/temporary-code-to-remove.md` in the project docs.
