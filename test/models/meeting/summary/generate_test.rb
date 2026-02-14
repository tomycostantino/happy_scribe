require "test_helper"

class Meeting::Summary::GenerateTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:content)

  setup do
    @meeting = meetings(:two)
    @meeting.update_column(:status, "processing")
    @transcript = transcripts(:two)
    @transcript.update_column(:status, "completed")

    @transcript.transcript_segments.create!(
      speaker: "Speaker 1", content: "Let's discuss the Q3 roadmap.",
      start_time: 0.0, end_time: 3.0, position: 0
    )
    @transcript.transcript_segments.create!(
      speaker: "Speaker 2", content: "I think we should focus on the API.",
      start_time: 3.0, end_time: 6.0, position: 1
    )
  end

  test "creates a summary from transcript via RubyLLM" do
    fake_response = "## Meeting Overview\nThe team discussed the Q3 roadmap."

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, FakeResponse.new(fake_response), [ String ])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      Meeting::Summary::Generate.perform_now(@meeting.id)
    end

    summary = @meeting.reload.summary
    assert_not_nil summary
    assert_includes summary.content.to_plain_text, "Q3 roadmap"
    assert_equal Rails.application.config.ai.default_model, summary.model_used

    mock_chat.verify
  end

  test "calls check_processing_complete! after creating summary" do
    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, FakeResponse.new("Summary content"), [ String ])

    @meeting.action_items.create!(description: "Test action")

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      Meeting::Summary::Generate.perform_now(@meeting.id)
    end

    assert_equal "completed", @meeting.reload.status
    mock_chat.verify
  end

  test "skips if summary already exists" do
    @meeting.create_summary!(model_used: "test")
    @meeting.summary.update!(content: "Existing summary")

    Meeting::Summary::Generate.perform_now(@meeting.id)

    assert_equal "Existing summary", @meeting.summary.content.to_plain_text
  end

  test "handles AI error gracefully — marks meeting as failed" do
    RubyLLM.stub(:chat, ->(**_kwargs) { raise StandardError, "API timeout" }) do
      Meeting::Summary::Generate.perform_now(@meeting.id)
    end

    assert_equal "failed", @meeting.reload.status
  end
end
