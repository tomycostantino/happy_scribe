---
targets: ["*"]
description: "Frontend conventions: Hotwire, Tailwind, Stimulus, ERB"
globs: ["app/views/**/*", "app/javascript/**/*", "app/assets/**/*"]
---

# Frontend

## Stack

- ERB templates
- Tailwind CSS via tailwindcss-rails (utility-first, no custom CSS unless necessary)
- Hotwire: Turbo for navigation and frames, Stimulus for JS behavior
- Import maps — no Node.js, no webpack/esbuild/vite
- Lexxy for rich text editing (Lexical-based, replaces Trix)

## Views

- Use ERB (not Slim, HAML, or other template engines)
- Use Tailwind utility classes directly in templates
- Extract repeated markup into partials
- Use `turbo_frame_tag` for partial page updates
- Prefix partial filenames with underscore: `_status.html.erb`

## Stimulus Controllers

- One behavior per controller
- Controllers live in `app/javascript/controllers/`
- Register via `controllers/index.js` (auto-loaded by stimulus-rails)
- Use `data-controller`, `data-action`, `data-target` attributes in ERB

## Tailwind

- Use utility classes directly — avoid `@apply` except in rare shared component styles
- Maintain consistent color usage (indigo for primary actions, status-specific colors for badges)
- Responsive design with Tailwind breakpoint prefixes

## JavaScript

- No npm packages — use import maps for external JS dependencies
- Keep JS minimal; prefer server-rendered HTML with Turbo
- Use Stimulus for interactive behavior, not inline `<script>` tags
