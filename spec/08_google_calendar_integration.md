# Spec 8: Google Calendar Integration (Deferred)

> **Status:** DEFERRED — Build this after Specs 1-7 are complete and the core pipeline works end-to-end.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to connect their Google account via OAuth2 and link calendar events to meetings, displaying attendees and agenda alongside the transcript.

**Architecture:** OmniAuth for Google OAuth2 flow, encrypted token storage, a `GoogleCalendar::Client` service for Calendar API calls. Entirely optional — the app works fully without it.

**Tech Stack:** `omniauth-google-oauth2` gem, `google-apis-calendar_v3` gem, Active Record Encryption.

**Dependencies:** Specs 1-7 must be complete first.

---

## Prerequisites (Gems to Add)

```ruby
# Gemfile — add these when implementing this spec
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "google-apis-calendar_v3"
```

---

## Data Model

### GoogleConnection

| Column | Type | Description |
|--------|------|-------------|
| `user_id` | references | FK to users |
| `email` | string | Google account email |
| `access_token` | string | Encrypted OAuth access token |
| `refresh_token` | string | Encrypted OAuth refresh token |
| `expires_at` | datetime | Token expiration time |

**Encryption:** Use Active Record Encryption for `access_token` and `refresh_token`.

```ruby
# app/models/google_connection.rb
class GoogleConnection < ApplicationRecord
  belongs_to :user

  encrypts :access_token
  encrypts :refresh_token

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def active?
    access_token.present? && !expired?
  end
end
```

**User association:**

```ruby
# app/models/user.rb — add
has_one :google_connection, dependent: :destroy
```

---

## OAuth Flow

### Task 1: OmniAuth Configuration

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV["GOOGLE_CLIENT_ID"],
    ENV["GOOGLE_CLIENT_SECRET"],
    {
      scope: "email,calendar.events.readonly",
      access_type: "offline",
      prompt: "consent" # Force refresh token on every auth
    }
end
```

### Task 2: OAuth Callbacks Controller

```ruby
# app/controllers/google_oauth_controller.rb
class GoogleOauthController < ApplicationController
  def callback
    auth = request.env["omniauth.auth"]

    google_connection = Current.user.google_connection || Current.user.build_google_connection
    google_connection.update!(
      email: auth.info.email,
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at: Time.at(auth.credentials.expires_at)
    )

    redirect_to meetings_path, notice: "Google Calendar connected successfully."
  end

  def failure
    redirect_to meetings_path, alert: "Google Calendar connection failed: #{params[:message]}"
  end

  def destroy
    Current.user.google_connection&.destroy
    redirect_to meetings_path, notice: "Google Calendar disconnected."
  end
end
```

### Task 3: Routes

```ruby
# config/routes.rb — add
get "/auth/google_oauth2/callback", to: "google_oauth#callback"
get "/auth/failure", to: "google_oauth#failure"
delete "/google_connection", to: "google_oauth#destroy"
```

---

## Calendar API Client

### Task 4: GoogleCalendar::Client Service

```ruby
# app/services/google_calendar/client.rb
module GoogleCalendar
  class Client
    def initialize(google_connection)
      @connection = google_connection
      refresh_token_if_needed!
    end

    # Find calendar events around a specific date
    # Returns events from 1 day before to 1 day after
    def find_events_around(date, query: nil)
      service = build_service

      time_min = (date - 1.day).beginning_of_day.iso8601
      time_max = (date + 1.day).end_of_day.iso8601

      result = service.list_events(
        "primary",
        time_min: time_min,
        time_max: time_max,
        q: query,
        single_events: true,
        order_by: "startTime",
        max_results: 20
      )

      result.items.map do |event|
        {
          id: event.id,
          summary: event.summary,
          description: event.description,
          start_time: event.start&.date_time || event.start&.date,
          end_time: event.end&.date_time || event.end&.date,
          attendees: (event.attendees || []).map { |a| { email: a.email, name: a.display_name } },
          html_link: event.html_link
        }
      end
    end

    private

    def build_service
      service = Google::Apis::CalendarV3::CalendarService.new
      service.authorization = google_authorization
      service
    end

    def google_authorization
      auth = Signet::OAuth2::Client.new(
        token_credential_uri: "https://oauth2.googleapis.com/token",
        client_id: ENV["GOOGLE_CLIENT_ID"],
        client_secret: ENV["GOOGLE_CLIENT_SECRET"],
        access_token: @connection.access_token,
        refresh_token: @connection.refresh_token
      )
      auth
    end

    def refresh_token_if_needed!
      return unless @connection.expired?

      auth = google_authorization
      auth.fetch_access_token!

      @connection.update!(
        access_token: auth.access_token,
        expires_at: Time.current + auth.expires_in.seconds
      )
    end
  end
end
```

---

## UI Integration

### Task 5: Meeting Show Page — Calendar Context

On the meeting show page, when a Google Calendar event is linked:

```erb
<%# Add to meetings/show.html.erb, after the header section %>
<% if @meeting.google_calendar_event_id.present? && @calendar_event.present? %>
  <div class="px-6 py-5 border-b border-gray-200 bg-blue-50">
    <h2 class="text-sm font-semibold text-blue-900 mb-2">Calendar Context</h2>
    <div class="text-sm text-blue-800">
      <p class="font-medium"><%= @calendar_event[:summary] %></p>
      <% if @calendar_event[:description].present? %>
        <p class="mt-1 text-blue-700"><%= truncate(@calendar_event[:description], length: 200) %></p>
      <% end %>
      <div class="mt-2 flex flex-wrap gap-2">
        <% @calendar_event[:attendees]&.each do |attendee| %>
          <span class="inline-flex items-center rounded-full bg-blue-100 px-2 py-0.5 text-xs text-blue-700">
            <%= attendee[:name] || attendee[:email] %>
          </span>
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

### Task 6: Link Calendar Event UI

Add a "Link Calendar Event" button that searches recent events:

```erb
<%# Add to meetings/show.html.erb when Google is connected but no event linked %>
<% if Current.user.google_connection&.active? && @meeting.google_calendar_event_id.blank? %>
  <div class="px-6 py-5 border-b border-gray-200">
    <%= turbo_frame_tag "calendar_link" do %>
      <%= link_to "Link Calendar Event",
        search_meeting_calendar_events_path(@meeting),
        class: "text-sm text-indigo-600 hover:text-indigo-500",
        data: { turbo_frame: "calendar_link" } %>
    <% end %>
  </div>
<% end %>
```

---

## Environment Variables Needed

```
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret
```

---

## Testing Strategy

- Use WebMock to stub Google Calendar API responses
- Test OAuth callback with mock OmniAuth auth hash
- Test token refresh logic
- Test event search and linking
- System test for the full connect → search → link flow

---

## Implementation Order

1. Add gems and run `bundle install`
2. Create migration for `google_connections` table
3. Create `GoogleConnection` model with encryption
4. Configure OmniAuth
5. Create `GoogleOauthController` with callback/failure/destroy
6. Create `GoogleCalendar::Client` service
7. Add calendar context UI to meeting show page
8. Add event search and linking flow
9. Write tests for all the above
