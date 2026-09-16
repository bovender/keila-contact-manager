# Keila Contact Manager — Project Handoff for Claude Code

## Context

Daniel is a senior physician-scientist and experienced Linux/Ruby developer
(Fedora KDE, Thinkpad P14s) working at Heidelberg University Hospital.
He self-hosts a Keila newsletter instance (keila.io) and has been managing
contacts with a small Ruby CLI toolset (see below). He now wants to build a
proper web-based contact manager for Keila as a standalone Rails application,
intended for public release on GitHub so other self-hosted Keila users can
benefit from it.

## Existing CLI Tools (starting point)

A small Ruby CLI project already exists with this structure:

```
keila2csv          # executable: Keila CSV export → flat CSV
csv2keila          # executable: flat CSV → Keila-importable CSV
keila_csv          # dispatcher entrypoint (used as Docker ENTRYPOINT)
lib/
  keila_csv_lib.rb # shared library (KeilaCsv module)
```

These tools handle the core data transformation challenge:
Keila stores custom contact fields as a JSON blob in a `data` column.
The lib flattens this to individual CSV columns and re-packs them for import.
Headers are read case-insensitively (Keila exports with capital first letters)
and written back in Keila's canonical capitalisation (Email, First_name, etc.).

The existing `keila_csv_lib.rb` logic should be absorbed into the Rails app.

## Keila's Data Model (relevant to this project)

Standard contact fields: Email, First_name, Last_name, External_id, Tags, Data
- `Tags` is a semicolon-separated list
- `Data` is a JSON object of arbitrary custom fields (varies per installation)

Keila is written in Elixir/Phoenix (PETAL stack) — contributing upstream is
not feasible. This app is an independent companion tool.

Keila does expose a REST API (Bearer token auth, available on self-hosted
instances), which should be used for live sync in addition to CSV import/export.

## Goals for the New Rails Application

### Must-have
- Import contacts from a Keila CSV export (flat or with JSON data column)
- Export contacts to a Keila-importable CSV
- Display contacts in a searchable, filterable table
- Edit individual contacts including custom data fields (dynamic form)
- Bulk operations: tag, untag, delete
- Configuration: Keila instance URL + API key (for live sync)

### Nice-to-have / future
- Live sync with Keila API (push/pull contacts without CSV)
- Segment preview (show which contacts match a given tag/field combination)
- Audit log of changes

## Technical Preferences

- **Language/framework:** Ruby on Rails (current stable version)
- **Daniel's Ruby background:** Commodore Basic → Turbo Pascal → Ruby/Rails;
  comfortable with ActiveRecord, MVC, standard Rails conventions
- **Weak spots:** JavaScript, npm — prefer Hotwire/Turbo/Stimulus over heavy JS
- **UI:** Keep it simple and functional; Tailwind is fine; no complex JS frontend
- **Auth:** Single-user or simple password protection is sufficient
  (this runs as a personal/small-team tool, not a multi-tenant SaaS)
- **Database:** SQLite for simplicity (self-hosted, single-user context)
- **Deployment:** Docker (Daniel already has a Dockerfile workflow);
  should be straightforward to self-host
- **OS:** Linux (Fedora); all tooling should be Linux-native

## Design Constraints

- Custom data fields are dynamic — the schema of `data` JSON varies between
  Keila installations. The app must handle unknown/arbitrary fields gracefully,
  not require migrations for new fields.
- The app should be useful standalone (CSV only) even without a Keila API key.
- Public GitHub release is planned — code should be clean, documented,
  and welcoming to other contributors.

## Suggested First Steps for Claude Code

1. `rails new keila_contact_manager --database=sqlite3 --css=tailwind`
2. Model: `Contact` with standard Keila fields as columns + a `data` jsonb/json
   column for custom fields
3. Port `KeilaCsv` module from `lib/keila_csv_lib.rb` as a Rails concern or
   service object
4. CSV import/export as the first working feature (no API needed yet)
5. Basic contact list view with search
6. Settings model/page for Keila URL + API token
