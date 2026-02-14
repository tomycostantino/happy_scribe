require "test_helper"
require "net/http"

class HappyScribe::ClientTest < ActiveSupport::TestCase
  setup do
    @client = HappyScribe::Client.new(api_key: "test_api_key", organization_id: "test_org_id")
  end

  test "initializes with api_key and organization_id" do
    client = HappyScribe::Client.new(api_key: "my_key", organization_id: "my_org")
    assert_instance_of HappyScribe::Client, client
  end

  test "initializes with defaults from credentials" do
    client = HappyScribe::Client.new
    assert_instance_of HappyScribe::Client, client
  end

  test "base_url defaults to production" do
    assert_equal "https://www.happyscribe.com", @client.base_url
  end

  test "base_url can be customized" do
    client = HappyScribe::Client.new(api_key: "key", organization_id: "org", base_url: "https://staging.happyscribe.com")
    assert_equal "https://staging.happyscribe.com", client.base_url
  end

  # --- Method existence and arity ---

  test "responds to get_signed_upload_url" do
    assert_respond_to @client, :get_signed_upload_url
  end

  test "responds to upload_to_signed_url" do
    assert_respond_to @client, :upload_to_signed_url
  end

  test "responds to create_transcription" do
    assert_respond_to @client, :create_transcription
  end

  test "responds to list_transcriptions" do
    assert_respond_to @client, :list_transcriptions
  end

  test "responds to retrieve_transcription" do
    assert_respond_to @client, :retrieve_transcription
  end

  test "responds to create_export" do
    assert_respond_to @client, :create_export
  end

  test "responds to retrieve_export" do
    assert_respond_to @client, :retrieve_export
  end

  test "responds to download" do
    assert_respond_to @client, :download
  end

  # --- handle_response behavior via test subclass ---

  test "handle_response returns parsed body for 200 response" do
    response = build_mock_response(code: "200", body: '{"id": "123"}')
    result = @client.send(:handle_response, response)
    assert_equal({ "id" => "123" }, result)
  end

  test "handle_response raises RateLimitError for 429 response" do
    response = build_mock_response(code: "429", body: '{"retry_in_seconds": 30}')
    error = assert_raises(HappyScribe::RateLimitError) do
      @client.send(:handle_response, response)
    end
    assert_equal 429, error.status
    assert_equal 30, error.retry_in
  end

  test "handle_response raises ApiError for 400 response" do
    response = build_mock_response(code: "400", message: "Bad Request", body: '{"error": "invalid"}')
    error = assert_raises(HappyScribe::ApiError) do
      @client.send(:handle_response, response)
    end
    assert_equal 400, error.status
    assert_equal({ "error" => "invalid" }, error.body)
  end

  test "handle_response raises ApiError for 500 response" do
    response = build_mock_response(code: "500", message: "Internal Server Error", body: '{"error": "server error"}')
    error = assert_raises(HappyScribe::ApiError) do
      @client.send(:handle_response, response)
    end
    assert_equal 500, error.status
  end

  test "handle_response handles empty body" do
    response = build_mock_response(code: "200", body: "")
    result = @client.send(:handle_response, response)
    assert_nil result
  end

  test "handle_response handles non-JSON body" do
    response = build_mock_response(code: "200", body: "plain text response")
    result = @client.send(:handle_response, response)
    assert_equal "plain text response", result
  end

  private

  def build_mock_response(code:, body: "", message: "OK")
    response = Data.define(:code, :body, :message).new(code: code, body: body, message: message)
    response
  end
end
