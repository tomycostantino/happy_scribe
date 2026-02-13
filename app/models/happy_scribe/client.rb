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
