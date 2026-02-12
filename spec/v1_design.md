# v1 Design Spec

## 1. Architecture Overview

The v1 is a Rails 8 application for a single user to upload meeting recordings, get AI-powered transcriptions with summaries and action items, and send follow-up emails.

### Stack

- **Framework:** Rails 8 with PostgreSQL (pg_vector extension for future semantic search)
- **Background Jobs:** Solid Queue (Rails 8 default)
- **Frontend:** Hotwire (Turbo + Stimulus) for real-time UI updates
- **AI:** RubyLLM for summaries and action item extraction
- **Transcription:** HappyScribe API
- **File Uploads:** Active Storage
- **Authentication:** Rails 8 built-in (email/password)
- **Optional:** Google OAuth connection for Calendar context

### Core Flow

1. User uploads audio/video file
2. Background job sends file to HappyScribe for transcription
3. Polling job monitors transcription progress
4. On completion, transcript is stored with speaker segments
5. AI processing jobs extract summary and action items via RubyLLM
6. Transcript chunks are embedded and stored (for future Q&A)
7. User can review summary, action items, and optionally send a follow-up email
8. If Google Calendar is connected, meeting context (attendees, agenda) is shown alongside the transcript

All processing is asynchronous. Turbo Streams broadcast status updates so the user sees real-time progress without refreshing.

### v1 Scope

**In scope:**

- Manual upload of audio/video files
- HappyScribe transcription with speaker
- AI-powered meeting summaries
- AI-powered action item extraction
- Transcript embeddings (stored for future use)
- Rails 8 built-in authentication
- Optional Google Calendar context
- Follow-up emails via Action Mailer / SMTP

**Deferred to v2:**

- Google Meet auto-import from Drive
- Gmail API sending (emails from user's own account)
- Meeting Q&A / RAG chat interface
- Scheduling intent detection and calendar event creation
- Teams / multi-user / shared access
