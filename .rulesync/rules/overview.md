---
root: true
targets: ["*"]
description: "Project overview and general development guidelines"
globs: ["**/*"]
---

# Happy Scribe

Rails 8.1 meeting transcription app. Users upload audio recordings, which are transcribed via the HappyScribe API, then processed with AI (RubyLLM) for summaries and action items.

## Tech Stack

- Ruby 4.0.0, Rails 8.1.2
- PostgreSQL 17 with pgvector extension
- Hotwire (Turbo + Stimulus) — no React/Vue/Angular
- Tailwind CSS via tailwindcss-rails
- Import maps — no Node.js bundler
- Solid Queue (background jobs), Solid Cache, Solid Cable
- Active Storage for file uploads
- Minitest for testing
- Kamal for deployment

## General Conventions

- Ruby code follows Rails Omakase style (RuboCop with rubocop-rails-omakase)
- 2 spaces for indentation
- Double quotes for strings
- No TypeScript or JavaScript bundler — use import maps and Stimulus
- Organize code by domain namespace, not by type
- Prefer composition via concerns over inheritance
- Keep related files close together under the same namespace
- Write self-documenting code; use comments only for complex business logic

## Architecture

- Models contain all business logic — no `app/services/` directory
- POROs live under model namespaces alongside ActiveRecord models (e.g. `HappyScribe::Transcription::Submit`)
- POROs use a `perform_now` class method pattern
- Jobs are thin wrappers that delegate to models (both POROs and ActiveRecord)
- State machines use Rails string enums (no state machine gem)
- Authentication uses Rails 8 built-in pattern with `Current` attributes and signed cookies

## Running the App

- `bin/dev` — starts web server, Tailwind watcher, and Solid Queue worker
- `bin/rails test` — run all tests
- `bin/rails test:system` — run system tests
- `bin/ci` — full CI suite (RuboCop, Brakeman, audit, tests)
- `docker compose up` — starts PostgreSQL

## Specs / Design Docs

Implementation plans live in `spec/` as numbered markdown files (01 through 08).
These are NOT test specs — they are design documents for planned features.
