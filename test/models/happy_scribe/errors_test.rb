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
