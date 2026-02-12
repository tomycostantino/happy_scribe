# Spec 3: Meeting Upload & Processing Pipeline

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the complete async pipeline from file upload through HappyScribe transcription to transcript storage, using chained background jobs.

**Architecture:** `MeetingsController#create` kicks off a 3-job chain: `SubmitTranscriptionJob` → `PollTranscriptionJob` → `FetchExportJob`. Jobs use `set(wait:)` for delays (not `sleep`) to keep Solid Queue workers free. Each job broadcasts Turbo Stream updates.

**Tech Stack:** Solid Queue, Active Storage, HappyScribe::Client (from Spec 2), Turbo Streams.

**Dependencies:** Spec 1 (models), Spec 2 (HappyScribe client).

---

## Pipeline Overview

```
User uploads file
  → MeetingsController#create
    → Saves Meeting (status: uploading) + Transcript (status: pending)
    → Attaches file via Active Storage
    → Enqueues SubmitTranscriptionJob

SubmitTranscriptionJob
  → Gets signed URL from HappyScribe
  → Uploads file to signed URL
  → Creates transcription via HappyScribe API
  → Saves happyscribe_id on Transcript
  → Meeting status → transcribing
  → Enqueues PollTranscriptionJob
  → Broadcasts status update

PollTranscriptionJob
  → Checks transcription status via HappyScribe API
  → If "automatic_done": creates export, enqueues FetchExportJob
  → If "failed": Meeting status → failed
  → Otherwise: re-enqueues self with exponential backoff
  → Broadcasts status update

FetchExportJob
  → Checks export status via HappyScribe API
  → If "ready": downloads JSON, parses segments, saves TranscriptSegments
  → Updates Transcript status → completed, Meeting status → transcribed
  → Enqueues AI jobs (GenerateSummaryJob, ExtractActionItemsJob, GenerateEmbeddingsJob)
  → If "failed": Meeting status → failed
  → Otherwise: re-enqueues self
  → Broadcasts status update
```

---

### Task 1: Routes

**Files:**
- Modify: `config/routes.rb`

**Step 1: Add meeting routes**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :meetings, only: [:index, :show, :new, :create, :destroy]

  get "up" => "rails/health#show", as: :rails_health_check

  root "meetings#index"
end
```

**Step 2: Verify routes**

Run: `bin/rails routes | grep meeting`
Expected: Shows index, show, new, create, destroy routes for meetings

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: add meeting routes and set root to meetings#index"
```

---

### Task 2: MeetingsController

**Files:**
- Create: `app/controllers/meetings_controller.rb`
- Test: `test/controllers/meetings_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/controllers/meetings_controller_test.rb
require "test_helper"

class MeetingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  # --- Index ---

  test "index shows user's meetings" do
    get meetings_url
    assert_response :success
    assert_select "h1", /meetings/i
  end

  test "index requires authentication" do
    sign_out
    get meetings_url
    assert_redirected_to new_session_url
  end

  # --- Show ---

  test "show displays meeting details" do
    get meeting_url(meetings(:one))
    assert_response :success
  end

  test "show returns 404 for other user's meeting" do
    sign_in_as(users(:two))
    assert_raises(ActiveRecord::RecordNotFound) do
      get meeting_url(meetings(:one))
    end
  end

  # --- New ---

  test "new shows upload form" do
    get new_meeting_url
    assert_response :success
    assert_select "form"
  end

  # --- Create ---

  test "create with valid file creates meeting and enqueues job" do
    file = fixture_file_upload("test/fixtures/files/sample.mp3", "audio/mpeg")

    assert_difference("Meeting.count") do
      assert_difference("Transcript.count") do
        assert_enqueued_with(job: SubmitTranscriptionJob) do
          post meetings_url, params: {
            meeting: {
              title: "New Meeting",
              language: "en-US",
              recording: file
            }
          }
        end
      end
    end

    meeting = Meeting.last
    assert_equal "New Meeting", meeting.title
    assert_equal "en-US", meeting.language
    assert_equal "uploading", meeting.status
    assert meeting.recording.attached?
    assert_redirected_to meeting_url(meeting)
  end

  test "create without title renders errors" do
    file = fixture_file_upload("test/fixtures/files/sample.mp3", "audio/mpeg")

    assert_no_difference("Meeting.count") do
      post meetings_url, params: {
        meeting: {
          title: "",
          language: "en-US",
          recording: file
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create without file renders errors" do
    assert_no_difference("Meeting.count") do
      post meetings_url, params: {
        meeting: {
          title: "Test",
          language: "en-US"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # --- Destroy ---

  test "destroy removes meeting and redirects" do
    assert_difference("Meeting.count", -1) do
      delete meeting_url(meetings(:two))
    end
    assert_redirected_to meetings_url
  end
end
```

**Step 2: Create test fixture file**

Create a small dummy audio file for tests:

Run: `dd if=/dev/zero of=test/fixtures/files/sample.mp3 bs=1024 count=1`

**Step 3: Run tests to verify they fail**

Run: `bin/rails test test/controllers/meetings_controller_test.rb`
Expected: FAIL — `NameError: uninitialized constant MeetingsController`

**Step 4: Implement the controller**

```ruby
# app/controllers/meetings_controller.rb
class MeetingsController < ApplicationController
  before_action :set_meeting, only: [:show, :destroy]

  def index
    @meetings = Current.user.meetings.order(created_at: :desc)
  end

  def show
  end

  def new
    @meeting = Meeting.new(language: "en-US")
  end

  def create
    @meeting = Current.user.meetings.build(meeting_params)

    unless @meeting.recording.attached? || meeting_params[:recording].present?
      @meeting.errors.add(:recording, "must be attached")
      render :new, status: :unprocessable_entity
      return
    end

    if @meeting.save
      @meeting.create_transcript!(status: :pending)
      SubmitTranscriptionJob.perform_later(@meeting.id)
      redirect_to @meeting, notice: "Meeting uploaded. Transcription will begin shortly."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @meeting.destroy!
    redirect_to meetings_url, notice: "Meeting deleted."
  end

  private

  def set_meeting
    @meeting = Current.user.meetings.find(params[:id])
  end

  def meeting_params
    params.require(:meeting).permit(:title, :language, :recording)
  end
end
```

**Step 5: Run tests**

Run: `bin/rails test test/controllers/meetings_controller_test.rb`
Expected: Some will fail because views don't exist yet — that's fine, views come in Spec 6.

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: add MeetingsController with create/upload pipeline"
```

---

### Task 3: SubmitTranscriptionJob

**Files:**
- Create: `app/jobs/submit_transcription_job.rb`
- Test: `test/jobs/submit_transcription_job_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/jobs/submit_transcription_job_test.rb
require "test_helper"

class SubmitTranscriptionJobTest < ActiveJob::TestCase
  setup do
    @meeting = meetings(:two) # status: uploading
    @transcript = transcripts(:two) # status: pending

    # Attach a fake recording
    @meeting.recording.attach(
      io: StringIO.new("fake audio data"),
      filename: "meeting.mp3",
      content_type: "audio/mpeg"
    )
  end

  test "uploads file and creates transcription on HappyScribe" do
    mock_client = Minitest::Mock.new

    # Expect: get signed URL
    mock_client.expect(:get_signed_upload_url, { "signedUrl" => "https://s3.example.com/signed" }, filename: "meeting.mp3")

    # Expect: upload to signed URL
    mock_client.expect(:upload_to_signed_url, true, signed_url: "https://s3.example.com/signed", file_data: "fake audio data", content_type: "audio/mpeg")

    # Expect: create transcription
    mock_client.expect(:create_transcription, {
      "id" => "hs_new_123",
      "state" => "ingesting"
    }, name: "Project Kickoff", language: "en-US", tmp_url: "https://s3.example.com/signed")

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: PollTranscriptionJob) do
        SubmitTranscriptionJob.perform_now(@meeting.id)
      end
    end

    @meeting.reload
    @transcript.reload

    assert_equal "transcribing", @meeting.status
    assert_equal "hs_new_123", @transcript.happyscribe_id
    assert_equal "processing", @transcript.status

    mock_client.verify
  end

  test "marks meeting as failed on API error" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:get_signed_upload_url, nil) do
      raise HappyScribe::ApiError.new("upload failed", status: 500)
    end

    HappyScribe::Client.stub(:new, mock_client) do
      SubmitTranscriptionJob.perform_now(@meeting.id)
    end

    assert_equal "failed", @meeting.reload.status
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/submit_transcription_job_test.rb`
Expected: FAIL

**Step 3: Implement the job**

```ruby
# app/jobs/submit_transcription_job.rb
class SubmitTranscriptionJob < ApplicationJob
  queue_as :default

  retry_on HappyScribe::RateLimitError, wait: :polynomially_longer, attempts: 5

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    transcript = meeting.transcript
    client = HappyScribe::Client.new

    # 1. Get signed upload URL
    filename = meeting.recording.filename.to_s
    signed_url_response = client.get_signed_upload_url(filename: filename)
    signed_url = signed_url_response["signedUrl"]

    # 2. Upload file to S3
    file_data = meeting.recording.download
    content_type = meeting.recording.content_type
    client.upload_to_signed_url(
      signed_url: signed_url,
      file_data: file_data,
      content_type: content_type
    )

    # 3. Create transcription on HappyScribe
    result = client.create_transcription(
      name: meeting.title,
      language: meeting.language,
      tmp_url: signed_url
    )

    # 4. Update local records
    transcript.update!(
      happyscribe_id: result["id"],
      status: :processing
    )
    meeting.update!(status: :transcribing)

    # 5. Enqueue polling job
    PollTranscriptionJob.perform_later(meeting.id)

    # 6. Broadcast status update
    broadcast_status(meeting)
  rescue HappyScribe::RateLimitError
    raise # Let retry_on handle it
  rescue StandardError => e
    meeting = Meeting.find(meeting_id)
    meeting.update!(status: :failed)
    broadcast_status(meeting)
    Rails.logger.error("SubmitTranscriptionJob failed for meeting #{meeting_id}: #{e.message}")
  end

  private

  def broadcast_status(meeting)
    Turbo::StreamsChannel.broadcast_replace_to(
      meeting,
      target: "meeting_#{meeting.id}_status",
      partial: "meetings/status",
      locals: { meeting: meeting }
    )
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/jobs/submit_transcription_job_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add SubmitTranscriptionJob for HappyScribe upload pipeline"
```

---

### Task 4: PollTranscriptionJob

**Files:**
- Create: `app/jobs/poll_transcription_job.rb`
- Test: `test/jobs/poll_transcription_job_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/jobs/poll_transcription_job_test.rb
require "test_helper"

class PollTranscriptionJobTest < ActiveJob::TestCase
  setup do
    @meeting = meetings(:two)
    @meeting.update!(status: :transcribing)
    @transcript = transcripts(:two)
    @transcript.update!(happyscribe_id: "hs_poll_test", status: :processing)
  end

  test "creates export when transcription is done" do
    mock_client = Minitest::Mock.new

    mock_client.expect(:retrieve_transcription, {
      "id" => "hs_poll_test",
      "state" => "automatic_done",
      "audioLengthInSeconds" => 120
    }, id: "hs_poll_test")

    mock_client.expect(:create_export, {
      "id" => "exp_001",
      "state" => "pending"
    }, transcription_ids: ["hs_poll_test"], format: "json", show_speakers: true)

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: FetchExportJob) do
        PollTranscriptionJob.perform_now(@meeting.id)
      end
    end

    @transcript.reload
    assert_equal "exp_001", @transcript.happyscribe_export_id
    assert_equal 120, @transcript.audio_length_seconds

    mock_client.verify
  end

  test "re-enqueues self when transcription is still processing" do
    mock_client = Minitest::Mock.new

    mock_client.expect(:retrieve_transcription, {
      "id" => "hs_poll_test",
      "state" => "automatic_transcribing"
    }, id: "hs_poll_test")

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: PollTranscriptionJob) do
        PollTranscriptionJob.perform_now(@meeting.id, poll_count: 0)
      end
    end

    # Meeting should still be transcribing
    assert_equal "transcribing", @meeting.reload.status

    mock_client.verify
  end

  test "marks meeting as failed when transcription fails" do
    mock_client = Minitest::Mock.new

    mock_client.expect(:retrieve_transcription, {
      "id" => "hs_poll_test",
      "state" => "failed",
      "failureReason" => "unsupported_format"
    }, id: "hs_poll_test")

    HappyScribe::Client.stub(:new, mock_client) do
      PollTranscriptionJob.perform_now(@meeting.id)
    end

    assert_equal "failed", @meeting.reload.status
    assert_equal "failed", @transcript.reload.status

    mock_client.verify
  end

  test "gives up after max poll count" do
    mock_client = Minitest::Mock.new

    mock_client.expect(:retrieve_transcription, {
      "id" => "hs_poll_test",
      "state" => "automatic_transcribing"
    }, id: "hs_poll_test")

    HappyScribe::Client.stub(:new, mock_client) do
      # At max poll count (360), should fail instead of re-enqueue
      PollTranscriptionJob.perform_now(@meeting.id, poll_count: 360)
    end

    assert_equal "failed", @meeting.reload.status

    mock_client.verify
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/poll_transcription_job_test.rb`
Expected: FAIL

**Step 3: Implement the job**

```ruby
# app/jobs/poll_transcription_job.rb
class PollTranscriptionJob < ApplicationJob
  queue_as :default

  MAX_POLLS = 360 # ~30 minutes at 5-second intervals
  BASE_WAIT = 5.seconds
  MAX_WAIT = 30.seconds

  def perform(meeting_id, poll_count: 0)
    meeting = Meeting.find(meeting_id)
    transcript = meeting.transcript
    client = HappyScribe::Client.new

    result = client.retrieve_transcription(id: transcript.happyscribe_id)
    state = result["state"]

    case state
    when "automatic_done"
      handle_done(meeting, transcript, result, client)
    when "failed", "locked"
      handle_failed(meeting, transcript, result)
    else
      handle_in_progress(meeting, poll_count)
    end

    broadcast_status(meeting)
  rescue StandardError => e
    meeting = Meeting.find(meeting_id)
    meeting.update!(status: :failed)
    broadcast_status(meeting)
    Rails.logger.error("PollTranscriptionJob failed for meeting #{meeting_id}: #{e.message}")
  end

  private

  def handle_done(meeting, transcript, result, client)
    transcript.update!(audio_length_seconds: result["audioLengthInSeconds"])

    # Create JSON export with speaker labels
    export_result = client.create_export(
      transcription_ids: [transcript.happyscribe_id],
      format: "json",
      show_speakers: true
    )

    transcript.update!(happyscribe_export_id: export_result["id"])

    FetchExportJob.perform_later(meeting.id)
  end

  def handle_failed(meeting, transcript, result)
    transcript.update!(status: :failed)
    meeting.update!(status: :failed)
    Rails.logger.error(
      "Transcription #{transcript.happyscribe_id} failed: #{result['failureReason']} - #{result['failureMessage']}"
    )
  end

  def handle_in_progress(meeting, poll_count)
    if poll_count >= MAX_POLLS
      meeting.update!(status: :failed)
      meeting.transcript.update!(status: :failed)
      Rails.logger.error("Transcription polling timed out for meeting #{meeting.id}")
      return
    end

    wait_time = [BASE_WAIT * (1.5**[poll_count, 10].min), MAX_WAIT].min
    PollTranscriptionJob.set(wait: wait_time).perform_later(meeting.id, poll_count: poll_count + 1)
  end

  def broadcast_status(meeting)
    Turbo::StreamsChannel.broadcast_replace_to(
      meeting,
      target: "meeting_#{meeting.id}_status",
      partial: "meetings/status",
      locals: { meeting: meeting }
    )
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/jobs/poll_transcription_job_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add PollTranscriptionJob with exponential backoff"
```

---

### Task 5: FetchExportJob

**Files:**
- Create: `app/jobs/fetch_export_job.rb`
- Test: `test/jobs/fetch_export_job_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/jobs/fetch_export_job_test.rb
require "test_helper"

class FetchExportJobTest < ActiveJob::TestCase
  setup do
    @meeting = meetings(:two)
    @meeting.update!(status: :transcribing)
    @transcript = transcripts(:two)
    @transcript.update!(
      happyscribe_id: "hs_fetch_test",
      happyscribe_export_id: "exp_fetch_test",
      status: :processing
    )
  end

  test "downloads and parses export when ready" do
    mock_client = Minitest::Mock.new

    # Export is ready
    mock_client.expect(:retrieve_export, {
      "id" => "exp_fetch_test",
      "state" => "ready",
      "download_link" => "https://cdn.example.com/export.json"
    }, id: "exp_fetch_test")

    # Download returns JSON transcript data
    export_json = {
      "words" => [
        { "speaker" => "Speaker 1", "text" => "Hello everyone.", "start" => 0.0, "end" => 2.0 },
        { "speaker" => "Speaker 1", "text" => " Welcome to the meeting.", "start" => 2.0, "end" => 4.0 },
        { "speaker" => "Speaker 2", "text" => "Thanks for having me.", "start" => 4.0, "end" => 6.0 }
      ]
    }.to_json

    mock_client.expect(:download, export_json, ["https://cdn.example.com/export.json"])

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: GenerateSummaryJob) do
        assert_enqueued_with(job: ExtractActionItemsJob) do
          assert_enqueued_with(job: GenerateEmbeddingsJob) do
            FetchExportJob.perform_now(@meeting.id)
          end
        end
      end
    end

    @transcript.reload
    @meeting.reload

    assert_equal "completed", @transcript.status
    assert_equal "transcribed", @meeting.status
    assert @transcript.transcript_segments.any?
    assert @transcript.raw_response.present?

    mock_client.verify
  end

  test "re-enqueues when export is still processing" do
    mock_client = Minitest::Mock.new

    mock_client.expect(:retrieve_export, {
      "id" => "exp_fetch_test",
      "state" => "processing"
    }, id: "exp_fetch_test")

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: FetchExportJob) do
        FetchExportJob.perform_now(@meeting.id, poll_count: 0)
      end
    end

    mock_client.verify
  end

  test "marks meeting as failed when export fails" do
    mock_client = Minitest::Mock.new

    mock_client.expect(:retrieve_export, {
      "id" => "exp_fetch_test",
      "state" => "failed"
    }, id: "exp_fetch_test")

    HappyScribe::Client.stub(:new, mock_client) do
      FetchExportJob.perform_now(@meeting.id)
    end

    assert_equal "failed", @meeting.reload.status

    mock_client.verify
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/fetch_export_job_test.rb`
Expected: FAIL

**Step 3: Implement the job**

```ruby
# app/jobs/fetch_export_job.rb
class FetchExportJob < ApplicationJob
  queue_as :default

  MAX_POLLS = 60 # ~3 minutes at 3-second intervals

  def perform(meeting_id, poll_count: 0)
    meeting = Meeting.find(meeting_id)
    transcript = meeting.transcript
    client = HappyScribe::Client.new

    result = client.retrieve_export(id: transcript.happyscribe_export_id)
    state = result["state"]

    case state
    when "ready"
      handle_ready(meeting, transcript, result, client)
    when "failed", "expired"
      handle_failed(meeting, transcript)
    else
      handle_in_progress(meeting, poll_count)
    end

    broadcast_status(meeting)
  rescue StandardError => e
    meeting = Meeting.find(meeting_id)
    meeting.update!(status: :failed)
    broadcast_status(meeting)
    Rails.logger.error("FetchExportJob failed for meeting #{meeting_id}: #{e.message}")
  end

  private

  def handle_ready(meeting, transcript, result, client)
    # Download the export JSON
    raw_json = client.download(result["download_link"])
    parsed = JSON.parse(raw_json)

    # Store raw response
    transcript.update!(raw_response: parsed)

    # Parse and save segments
    TranscriptParser.new(transcript, parsed).parse!

    # Build full text from segments
    transcript.update!(
      raw_content: transcript.formatted_text,
      status: :completed
    )

    meeting.update!(status: :transcribed)

    # Fan out to AI processing jobs (parallel)
    GenerateSummaryJob.perform_later(meeting.id)
    ExtractActionItemsJob.perform_later(meeting.id)
    GenerateEmbeddingsJob.perform_later(meeting.id)

    # Update meeting status to processing
    meeting.update!(status: :processing)
  end

  def handle_failed(meeting, transcript)
    transcript.update!(status: :failed)
    meeting.update!(status: :failed)
  end

  def handle_in_progress(meeting, poll_count)
    if poll_count >= MAX_POLLS
      meeting.update!(status: :failed)
      meeting.transcript.update!(status: :failed)
      return
    end

    FetchExportJob.set(wait: 3.seconds).perform_later(meeting.id, poll_count: poll_count + 1)
  end

  def broadcast_status(meeting)
    Turbo::StreamsChannel.broadcast_replace_to(
      meeting,
      target: "meeting_#{meeting.id}_status",
      partial: "meetings/status",
      locals: { meeting: meeting }
    )
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/jobs/fetch_export_job_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add FetchExportJob for downloading and parsing transcripts"
```

---

### Task 6: TranscriptParser Service

**Files:**
- Create: `app/services/transcript_parser.rb`
- Test: `test/services/transcript_parser_test.rb`

This service parses the HappyScribe JSON export format into `TranscriptSegment` records, grouping words by speaker.

**Step 1: Write the failing tests**

```ruby
# test/services/transcript_parser_test.rb
require "test_helper"

class TranscriptParserTest < ActiveSupport::TestCase
  setup do
    @transcript = transcripts(:two)
  end

  test "parses words into speaker segments" do
    # HappyScribe JSON export format — words grouped by speaker
    export_data = {
      "words" => [
        { "speaker" => "Speaker 1", "text" => "Hello ", "start" => 0.0, "end" => 1.0 },
        { "speaker" => "Speaker 1", "text" => "everyone.", "start" => 1.0, "end" => 2.0 },
        { "speaker" => "Speaker 2", "text" => "Hi ", "start" => 3.0, "end" => 3.5 },
        { "speaker" => "Speaker 2", "text" => "there.", "start" => 3.5, "end" => 4.0 },
        { "speaker" => "Speaker 1", "text" => "Let's ", "start" => 5.0, "end" => 5.5 },
        { "speaker" => "Speaker 1", "text" => "begin.", "start" => 5.5, "end" => 6.0 }
      ]
    }

    parser = TranscriptParser.new(@transcript, export_data)
    parser.parse!

    segments = @transcript.transcript_segments.order(:position)
    assert_equal 3, segments.count

    assert_equal "Speaker 1", segments[0].speaker
    assert_equal "Hello everyone.", segments[0].content
    assert_in_delta 0.0, segments[0].start_time
    assert_in_delta 2.0, segments[0].end_time
    assert_equal 0, segments[0].position

    assert_equal "Speaker 2", segments[1].speaker
    assert_equal "Hi there.", segments[1].content
    assert_in_delta 3.0, segments[1].start_time
    assert_in_delta 4.0, segments[1].end_time
    assert_equal 1, segments[1].position

    assert_equal "Speaker 1", segments[2].speaker
    assert_equal "Let's begin.", segments[2].content
    assert_in_delta 5.0, segments[2].start_time
    assert_in_delta 6.0, segments[2].end_time
    assert_equal 2, segments[2].position
  end

  test "handles empty words array" do
    parser = TranscriptParser.new(@transcript, { "words" => [] })
    parser.parse!

    assert_equal 0, @transcript.transcript_segments.count
  end

  test "handles single speaker" do
    export_data = {
      "words" => [
        { "speaker" => "Speaker 1", "text" => "Just me talking.", "start" => 0.0, "end" => 3.0 }
      ]
    }

    parser = TranscriptParser.new(@transcript, export_data)
    parser.parse!

    assert_equal 1, @transcript.transcript_segments.count
    assert_equal "Just me talking.", @transcript.transcript_segments.first.content
  end

  test "clears existing segments before parsing" do
    # Create a pre-existing segment
    @transcript.transcript_segments.create!(
      speaker: "Old", content: "Old content", position: 0
    )

    export_data = {
      "words" => [
        { "speaker" => "Speaker 1", "text" => "New content.", "start" => 0.0, "end" => 2.0 }
      ]
    }

    parser = TranscriptParser.new(@transcript, export_data)
    parser.parse!

    segments = @transcript.transcript_segments
    assert_equal 1, segments.count
    assert_equal "New content.", segments.first.content
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/transcript_parser_test.rb`
Expected: FAIL

**Step 3: Implement the parser**

```ruby
# app/services/transcript_parser.rb
class TranscriptParser
  def initialize(transcript, export_data)
    @transcript = transcript
    @export_data = export_data
  end

  def parse!
    # Clear existing segments
    @transcript.transcript_segments.destroy_all

    words = @export_data["words"] || []
    return if words.empty?

    segments = group_words_by_speaker(words)

    segments.each_with_index do |segment, index|
      @transcript.transcript_segments.create!(
        speaker: segment[:speaker],
        content: segment[:text].strip,
        start_time: segment[:start_time],
        end_time: segment[:end_time],
        position: index
      )
    end
  end

  private

  # Groups consecutive words by the same speaker into segments
  def group_words_by_speaker(words)
    segments = []
    current_segment = nil

    words.each do |word|
      speaker = word["speaker"]
      text = word["text"] || ""
      start_time = word["start"]
      end_time = word["end"]

      if current_segment.nil? || current_segment[:speaker] != speaker
        # Start a new segment
        segments << current_segment if current_segment
        current_segment = {
          speaker: speaker,
          text: text,
          start_time: start_time,
          end_time: end_time
        }
      else
        # Continue current segment
        current_segment[:text] += text
        current_segment[:end_time] = end_time
      end
    end

    segments << current_segment if current_segment
    segments
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/services/transcript_parser_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptParser service for HappyScribe JSON export parsing"
```
