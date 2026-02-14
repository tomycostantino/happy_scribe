# Action Item Email Tool with Contact Knowledge Base

## Goal

Enable users to send action item emails to meeting participants via the AI chat assistant. The AI builds a persistent knowledge base of contacts (name-to-email mapping) that grows over time.

## Architecture

Three new RubyLLM tools + a Contact model + the FollowUpEmail model from spec 01. All interaction happens through the existing chat interface.

## Data Models

### Contact (new)

```
contacts
  user_id    :bigint, not null, FK
  name       :string, not null
  email      :string, not null
  notes      :text
  timestamps

  unique index: [user_id, email]
  index: [user_id, name]
```

- `belongs_to :user`
- Email normalized (strip + downcase)
- `search_by_name` scope (ILIKE)

### FollowUpEmail (from spec 01)

```
follow_up_emails
  meeting_id  :bigint, not null, FK
  recipients  :string, not null
  subject     :string, not null
  sent_at     :datetime
  has_rich_text :body
  timestamps
```

- `belongs_to :meeting`
- `recipient_list` splits comma-separated emails
- `sent?` and `sent` scope

## Tools

### ContactLookupTool

Searches user's contacts by name. Returns formatted list with email and notes.

### ManageContactTool

Creates or updates contacts (upsert by email). Used by AI to remember email addresses.

### SendActionItemEmailTool

Two-phase flow:
- **Draft** (`action: "draft"`): Composes email preview from meeting action items
- **Send** (`action: "send"`): Creates FollowUpEmail record, delivers via FollowUpMailer

## Conversational Flow

```
User: "Email Sarah her action items from the weekly standup"
AI:   [ContactLookupTool] → finds Sarah Chen <sarah@company.com>
AI:   [SendActionItemEmailTool action:draft] → preview
AI:   "Here's the draft. Send it?"
User: "Yes"
AI:   [SendActionItemEmailTool action:send] → delivered
```

First-time contact:
```
User: "Email Sarah her action items"
AI:   [ContactLookupTool] → no match
AI:   "What's Sarah's email?"
User: "sarah@company.com"
AI:   [ManageContactTool] → saved
AI:   [continues with draft/send]
```

## Not In Scope

- Contact management UI
- Follow-up email compose UI (spec 07)
- Google Calendar attendee import (spec 08)
- Automatic/scheduled sending
- Email delivery tracking
