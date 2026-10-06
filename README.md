# Keila Contact Manager

A web-based contact manager for [Keila](https://www.keila.io/), the
self-hosted newsletter tool. It fills the gap between Keila's own contact
list UI and a spreadsheet: a searchable, filterable contact table with
inline editing of Keila's arbitrary custom data fields, plus CSV
import/export that round-trips cleanly with Keila's own export/import
format.

This is an independent companion project, not affiliated with Keila.

## Description

Keila Contact Manager (KCM) offers advanced contact management features
to work with lists of contacts in the Keila Open Source newsletter
software. It is bound to a single Keila instance. Projects within this
single Keila instance are projects in KCM. KCM is able to perform
two-way synchronization of contacts, and it knows when synchronization
is needed, either because the local data have been updated, the remote
contact list was changed, or both. It informs the user that synchronization
is due and offers a one-click synchronization trigger button.

KCM allows for an arbitrary number of additional data fields beyond
the built-in fields of Keila; the additional fields are stored in Keila's
`data` field. _Tags_ are a special kind of additional field that is native
to KCM -- tags can be filtered and toggled easily.

## Features

- Import contacts from a Keila CSV export (including the `Data` JSON
  column), or from a flat CSV with one column per custom field
- Export contacts back to a Keila-importable CSV
- Searchable, filterable contact table, including by tag and by any
  custom field
- Edit contacts, including custom data fields, through a normal web form
- Custom fields are schema-free: new ones show up automatically on import,
  or you can add them by hand, with no migration required
- Bulk tag, untag, and delete
- Finds likely duplicates — exact ones can't exist (emails are unique per
  project, ignoring case), so it looks for near misses: a typo in the
  domain or before the @, or the same name under two addresses — and
  merges two contacts into the one you choose to lead, or deletes one copy
- Two-way sync with Keila's REST API: the contacts page tells you when a
  sync is due (changes here, in Keila, or both) and syncs with one click;
  conflicting edits are shown side by side for you to decide
- Bound to one Keila instance; each of its projects is a project here,
  with its own contacts and custom fields — switch between them without
  their contacts ever mixing, even when the same email address exists in
  more than one
- Password login, or single sign-on via OpenID Connect (e.g. Keycloak) —
  this is a personal/small-team tool, not a multi-tenant SaaS

## Requirements

- Ruby (see [.ruby-version](.ruby-version)) and SQLite, **or**
- Docker and Docker Compose

## Quick start with Docker Compose

```sh
cp .env.example .env
# edit .env: set RAILS_MASTER_KEY, ADMIN_PASSWORD and KEILA_URL (see below)

docker compose up --build
```

The app will be available at <http://localhost:3000>. Log in with
`ADMIN_EMAIL` (defaults to `admin@example.com`) and `ADMIN_PASSWORD` from
your `.env` file. Contact data (SQLite databases) persists in a named
Docker volume across restarts.

`RAILS_MASTER_KEY` decrypts `config/credentials.yml.enc`, which holds the
key used to encrypt each project's Keila API key at rest (see
[Projects](#projects)). If you're running from a fresh clone without
`config/master.key`, generate credentials of your own first:

```sh
EDITOR=true bin/rails credentials:edit   # creates config/master.key
bin/rails db:encryption:init             # prints active_record_encryption keys
EDITOR="cat >>" bin/rails credentials:edit  # paste the printed block in
```

Then copy the contents of `config/master.key` into `.env` as
`RAILS_MASTER_KEY`.

## Local development setup

```sh
bin/setup
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=changeme bin/rails db:seed
bin/dev
```

`bin/dev` starts the Rails server together with the Tailwind CSS watcher.
Visit <http://localhost:3000> and sign in with the credentials you seeded.

Run the test suite with:

```sh
bin/rails test
```

### Running system tests

System tests (`test/system`) drive the app in a real browser via Selenium,
to exercise JavaScript-dependent behavior (Stimulus controllers, Turbo
forms) that request/model tests can't see. This sandbox has no local
Chrome, so they always run against a separately-hosted Chrome over
Selenium's remote WebDriver protocol — start one with Docker:

```sh
docker run -d --rm --name selenium \
  --add-host=host.docker.internal:host-gateway \
  --shm-size=2g -p 4444:4444 \
  selenium/standalone-chrome:latest

bin/rails db:test:prepare
bin/rails test:system
```

`--add-host` is what lets that container reach back to the Rails test
server Capybara starts on your machine (see
`test/application_system_test_case.rb`); CI's `system-test` job sets up
the same thing via its `selenium` service. If you're driving a different
remote Chrome (e.g. a Selenium Grid elsewhere), point at it with
`SELENIUM_REMOTE_URL` and `CAPYBARA_APP_HOST`.

### Continuous integration and deployment

Two workflows run the same checks (Brakeman, bundler-audit, importmap
audit, RuboCop, tests) without needing any secrets — the test environment
uses fixed, throwaway Active Record Encryption keys:

- `.github/workflows/ci.yml` on GitHub, which also runs the Selenium
  system tests.
- `.gitea/workflows/ci.yml` on a Gitea instance, which adds a `deploy`
  job: on pushes to `main`, once every check has passed, it runs `kamal
  deploy` (see [Deploying with Kamal](#deploying-with-kamal)). Since the
  Kamal destination files aren't in git, the job takes them from
  repository variables, and it only runs where they're set:
  `KAMAL_DESTINATION` (the destination's name), `KAMAL_DEPLOY_CONFIG`
  (the contents of `config/deploy.<name>.yml`) and `KAMAL_DEPLOY_SECRETS`
  (of `.kamal/secrets.<name>`), plus the secrets `RAILS_MASTER_KEY`
  (production), `KAMAL_REGISTRY_PASSWORD` and `KAMAL_DEPLOY_SSH_KEY` (a
  key the deploy user on the server accepts).

## Configuration

Environment variables:

| Variable | Purpose |
| --- | --- |
| `RAILS_MASTER_KEY` | Decrypts credentials in production/Docker (contents of `config/master.key`) |
| `KEILA_URL` | The Keila instance this app is bound to, e.g. `https://keila.example.com` |
| `APP_URL` | The app's public URL when hosted, e.g. `https://kcm.example.com`; served via `https`, the app trusts the reverse proxy's `X-Forwarded-Proto` and insists on SSL |
| `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` | Single sign-on, see below |
| `OIDC_PROVIDER_NAME` | Label on the sign-in button (optional) |
| `OIDC_REQUIRED_GROUP` | Only users with this group in their `groups` claim may sign in (optional) |
| `ADMIN_EMAIL` | Email for the initial user, created on first boot (default `admin@example.com`) |
| `ADMIN_PASSWORD` | Password for the initial user (required to create it) |

### Single sign-on (OpenID Connect)

Set `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` and `APP_URL`
to sign in through an OpenID Connect provider such as Keycloak, using a
confidential client with the redirect URI `APP_URL/auth/oidc/callback`
(and, for signing out of the provider too, the post-logout redirect URI
`APP_URL/session/new`). Single sign-on then replaces password login and
password reset entirely. Users are created on their first sign-in, and an
existing user with the same email address is taken over; who may sign in
is up to the provider (in Keycloak, e.g. by gating the client on a
group), optionally double-checked with `OIDC_REQUIRED_GROUP`.

### Projects

The app is bound to the one Keila instance at `KEILA_URL`, and a
**project** here is a project in that instance. Keila ties every API key
to exactly one project (and its API has no way to list projects), so you
add a project at `/keila_projects` by giving it a name and pasting an API
key created in Keila under that project's Settings → API. The key is
stored encrypted using Active Record Encryption.

Contacts are kept fully partitioned by project — the same email address
can exist in two projects as two entirely separate contacts — and custom
fields, search, CSV import/export and sync all operate only on whichever
project is currently active. Switch the active project from the nav bar
or the projects page. Removing a project only removes the local copy of
its contacts; nothing is deleted in Keila.

## Two-way sync with Keila

The contacts page checks the active project against Keila and shows
whether a sync is due: because contacts were changed here, in Keila
(edits, sign-ups, unsubscribes), or both. When there's nothing to decide,
**Sync now** does it in one click; otherwise the sync screen lists what
will happen first:

- A field changed on one side only is taken over by the other side.
  Fields changed on different sides of the same contact merge.
- A field changed on _both_ sides to different values is a **conflict**:
  the sync screen shows both values and you pick one.
- Contacts deleted on one side are deleted on the other, but only after
  the sync screen has shown you the list. A contact deleted on one side
  but changed on the other since is a conflict too: keep it or delete it.
- The very first sync of a project pairs up contacts that already exist
  on both sides (by this app's own id embedded in `Data`, then External
  ID, then email) and always goes through the sync screen.

This works by remembering, per contact, Keila's contact id and the state
both sides agreed on at the last sync, so each side can be compared
against it. Keila is only ever sent what changed: custom fields are
merged key by key, so a `Data` key added in Keila meanwhile (by a form,
or another integration) survives.

To exercise this against a real Keila instance rather than just the
stubbed test suite, `docker-compose.keila-dev.yml` spins one up
(separate from `docker-compose.yml`, this app's own self-hosting compose
file):

```sh
KEILA_SECRET_KEY_BASE=$(openssl rand -hex 64) \
  docker compose -f docker-compose.keila-dev.yml up -d
# Keila is now at http://localhost:4445; the generated root password is
# in `docker compose -f docker-compose.keila-dev.yml logs keila`.
# Sign in, create a project, generate an API key under its Settings ->
# API, then run this app with KEILA_URL=http://localhost:4445 and add a
# project with that key at /keila_projects.
```

## Deploying with Kamal

`config/deploy.yml` holds the [Kamal](https://kamal-deploy.org) settings
every deployment shares; your server's specifics go into a destination
file, `config/deploy.<name>.yml`, which is gitignored. Start from
`config/deploy.example.yml` (it assumes a reverse proxy of your own that
terminates TLS and forwards to kamal-proxy), and put the secrets into
`.kamal/secrets-common` (`RAILS_MASTER_KEY=$(cat config/master.key)`) and
`.kamal/secrets.<name>` (registry password, `OIDC_CLIENT_SECRET`), also
gitignored. Then:

```sh
bin/kamal setup -d <name>    # first deployment
bin/kamal deploy -d <name>
```

The container runs as uid/gid 1000 and keeps its SQLite databases in the
volume mounted at `/rails/storage`, so a host directory used for it must
be writable by that uid.

## Custom fields, tags, and the CSV format

Keila's own standard contact fields are `Email`, `First name`, `Last
name`, `External ID`, `Status`, and a `Data` JSON column for arbitrary
custom fields — checked directly against Keila's source, since it turns
out Keila has **no native concept of tags at all**, in its schema, its
own CSV export, or its API. (An earlier version of this README assumed
otherwise.)

This app mirrors Keila's shape: custom fields live in a single JSON
column per contact, and a small per-project registry
(`CustomFieldDefinition`) tracks which keys are known so they show up as
table columns and form fields — without ever needing a database
migration to add one.

**Tags are just one such custom field** — stored at the reserved key
`Contact::TAGS_DATA_KEY` ("Tags") inside `data`, so they travel through
`Data` on CSV export and API sync exactly like any other custom field.
What makes them different from an ordinary custom field is entirely at
the app layer: a permanent, non-deletable registry entry, and dedicated
UI (pills, tag filter, bulk tag/untag) since they're central to how
contacts get organized here. Re-importing a CSV replaces a contact's tag
list outright with whatever the file says, rather than merging it — for
tags specifically, "what the source says now" is more useful than "union
of everything ever seen." In two-way sync, a contact's tag list is one
field like any other (order doesn't matter).

- Importing a Keila export or syncing with unfamiliar `Data` keys (or
  unfamiliar flat CSV columns) registers them automatically.
- You can also add or remove fields from the registry directly at
  `/custom_field_definitions`. Removing a field from the registry only
  hides it from forms/table — existing contact data is kept. Tags can't
  be removed from the registry at all.
- Re-importing merges other custom field values into what's already
  there, rather than replacing it, so a periodic re-import from Keila
  won't wipe out fields you only maintain locally.

### Surviving an email change

Email addresses change. Keila's CSV export doesn't include Keila's own
internal contact ID, and `External_id` is optional and only as reliable as
whoever maintains it in Keila, so this app can't just match contacts by
email between imports without risking duplicates when an address changes.

Instead, every contact gets a permanent `uuid` on creation, which is
smuggled through Keila as a reserved key (`Kcm_uid`) inside the `Data`
JSON column on export. Re-importing a later Keila export matches contacts
in this order: by that embedded uuid, then by `External_id` if present,
and only then by email. The reserved key is stripped out on import and
can never appear as a regular custom field — it never needs your
attention.

One consequence: the very first export after adopting this app "plants"
the identifier in Keila. Contacts already living only in Keila won't be
protected against an email change until you've exported and re-imported
them into Keila at least once.

## Background

This project started as a small Ruby CLI toolset
(`keila2csv`/`csv2keila`) for converting between Keila's CSV export format
and a flat, spreadsheet-friendly one. See
[docs/CLAUDECODE_HANDOFF.md](docs/CLAUDECODE_HANDOFF.md) for the original
project handoff notes and design rationale.

## License

Apache License 2.0, see [LICENSE](LICENSE).
