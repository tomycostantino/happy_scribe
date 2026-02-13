---
targets: ["*"]
description: "HappyScribe API integration patterns and conventions"
globs: ["app/models/happy_scribe/**/*", "app/jobs/happy_scribe/**/*"]
---

# HappyScribe Integration

## API Client

`HappyScribe::Client` wraps all HappyScribe REST API calls using `Net::HTTP` (stdlib).
Authentication is via Bearer token from Rails encrypted credentials.

Do NOT introduce HTTP client gems (Faraday, HTTParty, etc.) — use Net::HTTP.

## Transcription Pipeline

The pipeline is a chain of jobs and POROs:

1. `SubmitJob` → `Submit.perform_now` — get signed URL, upload to S3, create transcription
2. `StatusPollJob` → `StatusPoll.perform_now` — poll until done, then create export
3. `ExportFetchJob` → `ExportFetch.perform_now` — poll export, download JSON, parse segments

Each step enqueues the next step's job when complete.

## Error Handling

Custom error hierarchy under `HappyScribe::`:

- `ApiError` — base, with status and body
- `RateLimitError` — 429 with retry_in
- `TranscriptionFailedError` — with reason

Jobs retry on `RateLimitError` with polynomial backoff. On unrecoverable errors,
the meeting is marked as `failed`.

## Polling Pattern

- `StatusPoll` uses exponential backoff: `BASE_WAIT * (1.5 ^ poll_count)` capped at MAX_WAIT
- `ExportFetch` uses fixed intervals
- Both track `poll_count` and have max poll limits
- Polling re-enqueues the same job with an incremented poll_count

## Thin Jobs, Fat Models

Jobs contain only retry configuration and a single `perform` call.
All business logic, error handling, and state transitions live in the POROs.
