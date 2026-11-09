# CoachNa Rails API

The backend for the CoachNa coach app, and later the restaurant web app and admin panel. The client app keeps its own backend, [`CoachNa_api`](https://github.com/AreejNour/CoachNa_api) (Node).

Runs on port **3003**. Everything is under a module for each product: coach routes are `/coach/*`, in `CoachApp`.

## Shared database: read this first

Development uses the **same database as the Node API**, and Node's migrations create the tables. Rails owns no tables yet.

Rails' usual setup commands would wipe that database, so `lib/shared_db_guard.rb` makes them refuse to run:

- `db:drop`, `db:purge`, `db:reset`, `db:setup`, `db:prepare`, `db:schema:load`, `db:migrate:reset`, `db:truncate_all`, `db:seed:replant` and `db:test:purge` only run against a database named `*_test`.
- `db:drop:all` and `db:purge:all` never run, because they reach every environment's database.

Don't remove the guard, and don't run `bin/rails db:migrate` in development. It would add Rails' own tables to the shared database. How Rails changes tables will be decided when it first needs to.

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

In `.env`, set `JWT_ACCESS_SECRET` to the **same value as the Node API's**. Each backend accepts coach tokens signed by the other, and Node's document routes need that until Milestone 17.

## Run and test

```bash
bin/rails server    # http://localhost:3003
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

No SMS is sent yet. Codes go to the log and, outside production, come back as `devCode`. See `docs/temporary-code-to-remove.md` in the project docs.
