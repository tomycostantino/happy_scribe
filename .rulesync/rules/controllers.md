---
targets: ["*"]
description: "Controller conventions: authentication, scoping, patterns"
globs: ["app/controllers/**/*"]
---

# Controllers

## Authentication

Rails 8 built-in authentication pattern:

- `Authentication` concern included in `ApplicationController`
- `require_authentication` before_action on all controllers by default
- `Current.user` provides the authenticated user via `ActiveSupport::CurrentAttributes`
- Sessions stored as signed cookies referencing a `Session` model
- Use `allow_unauthenticated_access` for public actions (login, password reset)

## Conventions

- Scope all queries to `Current.user` (e.g. `Current.user.meetings`)
- Keep controllers thin — delegate business logic to models
- Use strong parameters via private `*_params` methods
- Use `rate_limit` for sensitive actions (e.g. login attempts)
- Respond with standard Rails flash messages for success/error states

## RESTful Design

- Stick to standard CRUD actions: index, show, new, create, edit, update, destroy
- Use `resources` / `resource` in routes — avoid custom routes unless necessary
- Use singular `resource` for things that exist once per user (e.g. session)

## Error Handling

- Let ActiveRecord::RecordNotFound raise naturally (Rails returns 404)
- Use `redirect_to` with flash for user-facing errors
- Log unexpected errors; don't silently swallow exceptions
