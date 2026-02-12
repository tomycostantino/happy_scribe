# Spec 2: HappyScribe API Integration

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a service layer that wraps all HappyScribe Product API calls needed for the transcription pipeline.

**Architecture:** A `HappyScribe::Client` class using `Net::HTTP` (stdlib) with methods for upload, transcription creation, polling, export creation, and export retrieval. Custom error classes for error handling.

**Tech Stack:** Net::HTTP (stdlib), JSON (stdlib). No extra gems. Auth via `ENV["HAPPY_SCRIBE_API_KEY"]`.

**Reference:** [HappyScribe Product API docs](https://dev.happyscribe.com/sections/product/)

---

## API Endpoints Used

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/api/v1/uploads/new?filename=X` | Get signed S3 URL for file upload |
| `PUT` | `{signedUrl}` | Upload file to S3 |
| `POST` | `/api/v1/transcriptions` | Create a transcription (legacy endpoint) |
| `GET` | `/api/v1/transcriptions/<ID>` | Poll transcription status |
| `POST` | `/api/v1/exports` | Create a JSON export with speakers |
| `GET` | `/api/v1/exports/<ID>` | Get export status + download link |

## Authentication

All requests include header: `Authorization: Bearer {HAPPY_SCRIBE_API_KEY}`

## Key States

**Transcription:** `initial` → `ingesting` → `automatic_transcribing` → `automatic_done` | `failed` | `locked`

**Export:** `pending` → `processing` → `ready` | `expired` | `failed`

---

### Task 1: Error Classes

**Files:**
- Create: `app/services/happy_scribe/errors.rb`
- Test: `test/services/happy_scribe/errors_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/services/happy_scribe/errors_test.rb
require "test_helper"

class HappyScribe::ErrorsTest < ActiveSupport::TestCase
  test "ApiError is a StandardError" do
    error = HappyScribe::ApiError.new("something went wrong")
    assert_kind_of StandardError, error
    assert_equal "something went wrong", error.message
  end

  test "ApiError stores status code and body" do
    error = HappyScribe::ApiError.new("bad request", status: 400, body: { "error" => "invalid" })
    assert_equal 400, error.status
    assert_equal({ "error" => "invalid" }, error.body)
  end

  test "RateLimitError is an ApiError" do
    error = HappyScribe::RateLimitError.new("too many requests", retry_in: 30)
    assert_kind_of HappyScribe::ApiError, error
    assert_equal 30, error.retry_in
  end

  test "TranscriptionFailedError is an ApiError" do
    error = HappyScribe::TranscriptionFailedError.new("transcription failed", reason: "unsupported_format")
    assert_kind_of HappyScribe::ApiError, error
    assert_equal "unsupported_format", error.reason
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/happy_scribe/errors_test.rb`
Expected: FAIL — `NameError: uninitialized constant HappyScribe`

**Step 3: Create the error classes**

```ruby
# app/services/happy_scribe/errors.rb
module HappyScribe
  class ApiError < StandardError
    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      @status = status
      @body = body
      super(message)
    end
  end

  class RateLimitError < ApiError
    attr_reader :retry_in

    def initialize(message = nil, retry_in: nil, **kwargs)
      @retry_in = retry_in
      super(message, **kwargs)
    end
  end

  class TranscriptionFailedError < ApiError
    attr_reader :reason

    def initialize(message = nil, reason: nil, **kwargs)
      @reason = reason
      super(message, **kwargs)
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/services/happy_scribe/errors_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add HappyScribe error classes"
```

---

### Task 2: Client — Core HTTP Methods

**Files:**
- Create: `app/services/happy_scribe/client.rb`
- Test: `test/services/happy_scribe/client_test.rb`

**Step 1: Write the failing tests for core HTTP plumbing**

```ruby
# test/services/happy_scribe/client_test.rb
require "test_helper"
require "net/http"

class HappyScribe::ClientTest < ActiveSupport::TestCase
  setup do
    @client = HappyScribe::Client.new(api_key: "test_api_key")
  end

  test "initializes with api_key" do
    client = HappyScribe::Client.new(api_key: "my_key")
    assert_instance_of HappyScribe::Client, client
  end

  test "initializes with default api_key from ENV" do
    ENV.stub(:[], "HAPPY_SCRIBE_API_KEY") do
      # Test that it reads from ENV when no key is provided
      client = HappyScribe::Client.new
      assert_instance_of HappyScribe::Client, client
    end
  end

  test "base_url defaults to production" do
    assert_equal "https://www.happyscribe.com", @client.base_url
  end

  # --- get_signed_upload_url ---

  test "get_signed_upload_url makes GET request with filename" do
    stub_response = { "signedUrl" => "https://s3.amazonaws.com/bucket/file?signature=abc" }

    @client.stub(:get, stub_response) do
      result = @client.get_signed_upload_url(filename: "meeting.mp3")
      assert_equal "https://s3.amazonaws.com/bucket/file?signature=abc", result["signedUrl"]
    end
  end

  # --- create_transcription ---

  test "create_transcription posts with required params" do
    stub_response = {
      "id" => "hs_abc123",
      "name" => "My Meeting",
      "state" => "ingesting",
      "language" => "en-US"
    }

    @client.stub(:post, stub_response) do
      result = @client.create_transcription(
        name: "My Meeting",
        language: "en-US",
        tmp_url: "https://s3.amazonaws.com/file.mp3"
      )
      assert_equal "hs_abc123", result["id"]
      assert_equal "ingesting", result["state"]
    end
  end

  # --- retrieve_transcription ---

  test "retrieve_transcription gets transcription by id" do
    stub_response = {
      "id" => "hs_abc123",
      "state" => "automatic_done",
      "audioLengthInSeconds" => 120
    }

    @client.stub(:get, stub_response) do
      result = @client.retrieve_transcription(id: "hs_abc123")
      assert_equal "automatic_done", result["state"]
      assert_equal 120, result["audioLengthInSeconds"]
    end
  end

  # --- create_export ---

  test "create_export posts with transcription_ids and format" do
    stub_response = {
      "id" => "export_001",
      "state" => "pending",
      "format" => "json"
    }

    @client.stub(:post, stub_response) do
      result = @client.create_export(
        transcription_ids: ["hs_abc123"],
        format: "json",
        show_speakers: true
      )
      assert_equal "export_001", result["id"]
      assert_equal "pending", result["state"]
    end
  end

  # --- retrieve_export ---

  test "retrieve_export gets export by id" do
    stub_response = {
      "id" => "export_001",
      "state" => "ready",
      "download_link" => "https://example.com/download/export.json"
    }

    @client.stub(:get, stub_response) do
      result = @client.retrieve_export(id: "export_001")
      assert_equal "ready", result["state"]
      assert_equal "https://example.com/download/export.json", result["download_link"]
    end
  end

  # --- Error handling ---

  test "raises RateLimitError on 429 response" do
    error_body = { "retry_in_seconds" => 30 }

    @client.stub(:handle_response, ->(_) { raise HappyScribe::RateLimitError.new("rate limited", retry_in: 30) }) do
      assert_raises(HappyScribe::RateLimitError) do
        @client.retrieve_transcription(id: "test")
      end
    end
  end

  test "raises ApiError on 4xx/5xx responses" do
    @client.stub(:handle_response, ->(_) { raise HappyScribe::ApiError.new("bad request", status: 400) }) do
      assert_raises(HappyScribe::ApiError) do
        @client.retrieve_transcription(id: "test")
      end
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/happy_scribe/client_test.rb`
Expected: FAIL

**Step 3: Implement the client**

```ruby
# app/services/happy_scribe/client.rb
require "net/http"
require "json"
require "uri"

module HappyScribe
  class Client
    BASE_URL = "https://www.happyscribe.com"

    attr_reader :base_url

    def initialize(api_key: nil, base_url: BASE_URL)
      @api_key = api_key || ENV.fetch("HAPPY_SCRIBE_API_KEY")
      @base_url = base_url
    end

    # Step 1: Get a signed S3 URL for uploading a file
    # GET /api/v1/uploads/new?filename=X
    def get_signed_upload_url(filename:)
      get("/api/v1/uploads/new", filename: filename)
    end

    # Step 2: Upload file data to the signed S3 URL
    # PUT {signedUrl} with raw file body
    def upload_to_signed_url(signed_url:, file_data:, content_type: "application/octet-stream")
      uri = URI.parse(signed_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = 300 # 5 min for large files

      request = Net::HTTP::Put.new(uri)
      request["Content-Type"] = content_type
      request.body = file_data

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError.new(
          "Upload failed: #{response.code} #{response.message}",
          status: response.code.to_i,
          body: response.body
        )
      end

      true
    end

    # Step 3: Create a transcription from the uploaded file URL
    # POST /api/v1/transcriptions
    def create_transcription(name:, language:, tmp_url:)
      post("/api/v1/transcriptions", {
        transcription: {
          name: name,
          language: language,
          tmp_url: tmp_url,
          is_subtitle: false
        }
      })
    end

    # Step 4: Check transcription status
    # GET /api/v1/transcriptions/<ID>
    def retrieve_transcription(id:)
      get("/api/v1/transcriptions/#{id}")
    end

    # Step 5: Create a JSON export with speaker labels
    # POST /api/v1/exports
    def create_export(transcription_ids:, format: "json", show_speakers: true)
      post("/api/v1/exports", {
        export: {
          format: format,
          transcription_ids: transcription_ids,
          show_speakers: show_speakers
        }
      })
    end

    # Step 6: Check export status and get download link
    # GET /api/v1/exports/<ID>
    def retrieve_export(id:)
      get("/api/v1/exports/#{id}")
    end

    # Download content from a URL (used for export download_link)
    def download(url)
      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPRedirection)
        response = Net::HTTP.get_response(URI.parse(response["location"]))
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError.new(
          "Download failed: #{response.code}",
          status: response.code.to_i
        )
      end

      response.body
    end

    private

    def get(path, params = {})
      uri = build_uri(path, params)
      request = Net::HTTP::Get.new(uri)
      execute(uri, request)
    end

    def post(path, body)
      uri = build_uri(path)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      execute(uri, request)
    end

    def execute(uri, request)
      request["Authorization"] = "Bearer #{@api_key}"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = 30

      response = http.request(request)
      handle_response(response)
    end

    def handle_response(response)
      body = parse_body(response.body)

      case response.code.to_i
      when 200..299
        body
      when 429
        retry_in = body.is_a?(Hash) ? body["retry_in_seconds"] : nil
        raise RateLimitError.new(
          "Rate limited by HappyScribe API",
          status: 429,
          body: body,
          retry_in: retry_in
        )
      else
        raise ApiError.new(
          "HappyScribe API error: #{response.code} #{response.message}",
          status: response.code.to_i,
          body: body
        )
      end
    end

    def build_uri(path, params = {})
      uri = URI.parse("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      uri
    end

    def parse_body(body)
      return nil if body.nil? || body.empty?
      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/services/happy_scribe/client_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add HappyScribe::Client with all API methods"
```

---

### Task 3: Configuration Initializer

**Files:**
- Create: `config/initializers/happy_scribe.rb`

**Step 1: Create the initializer**

```ruby
# config/initializers/happy_scribe.rb
Rails.application.config.happy_scribe = ActiveSupport::OrderedOptions.new
Rails.application.config.happy_scribe.api_key = ENV["HAPPY_SCRIBE_API_KEY"]
Rails.application.config.happy_scribe.organization_id = ENV["HAPPY_SCRIBE_ORGANIZATION_ID"]
```

**Step 2: Add to .env.example (if it exists) or document in README**

Environment variables needed:
```
HAPPY_SCRIBE_API_KEY=your_api_key_here
HAPPY_SCRIBE_ORGANIZATION_ID=your_org_id_here
```

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: add HappyScribe configuration initializer"
```

---

### Task 4: Integration Test with Mocked HTTP

**Files:**
- Create: `test/services/happy_scribe/client_integration_test.rb`

This test exercises the full flow with stubbed HTTP responses, verifying the client correctly composes requests and parses responses.

**Step 1: Write the integration test**

```ruby
# test/services/happy_scribe/client_integration_test.rb
require "test_helper"
require "webmock" # Note: add webmock gem to test group in Gemfile

class HappyScribe::ClientIntegrationTest < ActiveSupport::TestCase
  setup do
    @client = HappyScribe::Client.new(api_key: "test_key")
  end

  test "full transcription flow: upload -> create -> poll -> export -> download" do
    # Step 1: Get signed URL
    stub_request(:get, "https://www.happyscribe.com/api/v1/uploads/new?filename=meeting.mp3")
      .with(headers: { "Authorization" => "Bearer test_key" })
      .to_return(
        status: 200,
        body: { signedUrl: "https://s3.amazonaws.com/bucket/meeting.mp3?sig=abc" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @client.get_signed_upload_url(filename: "meeting.mp3")
    assert_equal "https://s3.amazonaws.com/bucket/meeting.mp3?sig=abc", result["signedUrl"]

    # Step 2: Upload file (PUT to S3)
    stub_request(:put, "https://s3.amazonaws.com/bucket/meeting.mp3?sig=abc")
      .to_return(status: 200)

    assert @client.upload_to_signed_url(
      signed_url: "https://s3.amazonaws.com/bucket/meeting.mp3?sig=abc",
      file_data: "fake audio data"
    )

    # Step 3: Create transcription
    stub_request(:post, "https://www.happyscribe.com/api/v1/transcriptions")
      .with(
        headers: { "Authorization" => "Bearer test_key", "Content-Type" => "application/json" },
        body: hash_including("transcription" => hash_including("name" => "My Meeting"))
      )
      .to_return(
        status: 201,
        body: { id: "hs_123", state: "ingesting", name: "My Meeting" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @client.create_transcription(
      name: "My Meeting",
      language: "en-US",
      tmp_url: "https://s3.amazonaws.com/bucket/meeting.mp3?sig=abc"
    )
    assert_equal "hs_123", result["id"]
    assert_equal "ingesting", result["state"]

    # Step 4: Poll transcription — first returns in-progress, then done
    stub_request(:get, "https://www.happyscribe.com/api/v1/transcriptions/hs_123")
      .to_return(
        { status: 200, body: { id: "hs_123", state: "automatic_transcribing" }.to_json,
          headers: { "Content-Type" => "application/json" } },
        { status: 200, body: { id: "hs_123", state: "automatic_done", audioLengthInSeconds: 120 }.to_json,
          headers: { "Content-Type" => "application/json" } }
      )

    result = @client.retrieve_transcription(id: "hs_123")
    assert_equal "automatic_transcribing", result["state"]

    result = @client.retrieve_transcription(id: "hs_123")
    assert_equal "automatic_done", result["state"]

    # Step 5: Create export
    stub_request(:post, "https://www.happyscribe.com/api/v1/exports")
      .to_return(
        status: 200,
        body: { id: "exp_456", state: "pending", format: "json" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @client.create_export(transcription_ids: ["hs_123"])
    assert_equal "exp_456", result["id"]

    # Step 6: Retrieve export
    stub_request(:get, "https://www.happyscribe.com/api/v1/exports/exp_456")
      .to_return(
        status: 200,
        body: { id: "exp_456", state: "ready", download_link: "https://cdn.example.com/export.json" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = @client.retrieve_export(id: "exp_456")
    assert_equal "ready", result["state"]
    assert_equal "https://cdn.example.com/export.json", result["download_link"]
  end

  test "handles 429 rate limit response" do
    stub_request(:get, "https://www.happyscribe.com/api/v1/transcriptions/hs_123")
      .to_return(
        status: 429,
        body: { retry_in_seconds: 30 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    error = assert_raises(HappyScribe::RateLimitError) do
      @client.retrieve_transcription(id: "hs_123")
    end
    assert_equal 429, error.status
    assert_equal 30, error.retry_in
  end

  test "handles 401 unauthorized response" do
    stub_request(:get, "https://www.happyscribe.com/api/v1/transcriptions/hs_123")
      .to_return(
        status: 401,
        body: { error: "Unauthorized" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    error = assert_raises(HappyScribe::ApiError) do
      @client.retrieve_transcription(id: "hs_123")
    end
    assert_equal 401, error.status
  end
end
```

**Step 2: Add `webmock` to Gemfile test group**

```ruby
# Gemfile — add to test group
gem "webmock"
```

Run: `bundle install`

**Step 3: Run integration tests**

Run: `bin/rails test test/services/happy_scribe/client_integration_test.rb`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add -A && git commit -m "test: add HappyScribe::Client integration tests with webmock"
```
