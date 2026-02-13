---
targets: ["*"]
description: "Model conventions, concerns, POROs, and domain patterns"
globs: ["app/models/**/*"]
---

# Models

## Organization

Models are organized by domain namespace:

- `app/models/concerns/` — globally shared concerns (used across multiple models)
- `app/models/meeting/` — Meeting-specific concerns (Recordable, Transcribable)
- `app/models/transcript/` — Transcript-specific concerns (Parseable, Formattable)
- `app/models/happy_scribe/` — API client, errors, and transcription POROs

## Concerns

- **Global concerns** go in `app/models/concerns/` when shared across multiple models
- **Model-specific concerns** are namespaced under their parent model:
  - `Meeting::Recordable` lives in `app/models/meeting/recordable.rb`
  - `Transcript::Parseable` lives in `app/models/transcript/parseable.rb`

## POROs

Plain Old Ruby Objects live alongside ActiveRecord models under domain namespaces.
They use a `perform_now` class method pattern if they're called by a job:

```ruby
module HappyScribe
  module Transcription
    class Submit
      def self.perform_now(transcript)
        # ...
      end
    end
  end
end
```

## State Management

Use Rails string enums for status tracking. No state machine gems.

```ruby
enum :status, {
  uploading: "uploading",
  transcribing: "transcribing",
  completed: "completed",
  failed: "failed"
}
```

## Associations and Callbacks

- Use `after_create_commit` (not `after_create`) for triggering async work
- Scope associations to the owning user at the controller level
- Keep validations in the model; keep authorization in the controller

## Error Classes

Custom errors live under their domain namespace:

- `HappyScribe::ApiError` — base API error with status and body
- `HappyScribe::RateLimitError` — 429 errors with retry_in
- `HappyScribe::TranscriptionFailedError` — failure with reason
