# Keila Contact Manager

A web-based contact manager for [Keila](https://www.keila.io/), the
self-hosted newsletter tool. It fills the gap between Keila's own contact
list UI and a spreadsheet: a searchable, filterable contact table with
inline editing of Keila's arbitrary custom data fields, plus CSV
import/export that round-trips cleanly with Keila's own export/import
format.

This is an independent companion project, not affiliated with Keila.

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
- Single-user login (this is a personal/small-team tool, not a multi-tenant
  SaaS)

## Requirements

- Ruby (see [.ruby-version](.ruby-version)) and SQLite, **or**
- Docker and Docker Compose

## Quick start with Docker Compose

```sh
cp .env.example .env
# edit .env: set RAILS_MASTER_KEY and ADMIN_PASSWORD (see below)

docker compose up --build
```

The app will be available at <http://localhost:3000>. Log in with
`ADMIN_EMAIL` (defaults to `admin@example.com`) and `ADMIN_PASSWORD` from
your `.env` file. Contact data (SQLite databases) persists in a named
Docker volume across restarts.

`RAILS_MASTER_KEY` decrypts `config/credentials.yml.enc`, which holds the
key used to encrypt the Keila API key at rest (see
[Settings](#settings)). If you're running from a fresh clone without
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

### Continuous integration

The GitHub Actions workflow (`.github/workflows/ci.yml`) needs a
`RAILS_MASTER_KEY` repository secret to decrypt credentials for the test
job (the Active Record Encryption keys used for the settings' API key
live there). **Use the test-environment key, not your production one:**
this repo ships `config/credentials/test.yml.enc`, decrypted by
`config/credentials/test.key` (gitignored, generated locally by
`bin/rails credentials:edit --environment test`). Add its contents as the
`RAILS_MASTER_KEY` secret under repo Settings → Secrets and variables →
Actions. Keeping test and production credentials on separate keys means a
compromised CI run can never expose the key protecting real Keila API
keys in production.

## Configuration

Environment variables:

| Variable | Purpose |
| --- | --- |
| `RAILS_MASTER_KEY` | Decrypts credentials in production/Docker (contents of `config/master.key`) |
| `ADMIN_EMAIL` | Email for the initial user, created on first boot (default `admin@example.com`) |
| `ADMIN_PASSWORD` | Password for the initial user (required to create it) |

### Settings

The in-app Settings page (`/settings/edit`) stores your Keila instance URL
and API key, for future live-sync features. The API key is encrypted at
rest using Active Record Encryption. The app is fully usable via CSV
import/export alone without ever filling this in.

## Custom fields and the CSV format

Keila stores standard fields (`Email`, `First_name`, `Last_name`,
`External_id`, `Status`, `Tags`) as plain CSV columns, semicolon-separated
tags, and any custom fields as a JSON object in a `Data` column. This app
mirrors that: custom fields live in a single JSON column per contact, and
a small registry (`CustomFieldDefinition`) tracks which keys are known so
they show up as table columns and form fields — without ever needing a
database migration to add one.

- Importing a Keila export with unfamiliar `Data` keys (or unfamiliar flat
  columns) registers them automatically.
- You can also add, rename, or remove fields from the registry directly
  at `/custom_field_definitions`. Removing a field from the registry only
  hides it from forms/table — existing contact data is kept.
- Re-importing merges custom field values into what's already there,
  rather than replacing it, so a periodic re-import from Keila won't wipe
  out fields you only maintain locally.

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
