require "test_helper"

class ChatResponseJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "job is enqueued on llm queue" do
    assert_equal "llm", ChatResponseJob.new.queue_name
  end

  test "retries on RubyLLM::Error" do
    handlers = ChatResponseJob.rescue_handlers
    assert handlers.any? { |h| h.first == "RubyLLM::Error" }
  end
end
