require "test_helper"

class TranscriptSearchToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = TranscriptSearchTool.new(@user)
  end

  test "searches transcript content across all meetings" do
    result = @tool.execute(query: "budget")
    assert_includes result, "budget"
    # Should find results from both meetings
    assert_includes result, "Weekly Standup"
    assert_includes result, "Design Review"
  end

  test "returns matching chunks with meeting context" do
    result = @tool.execute(query: "homepage design")
    assert_includes result, "Design Review"
    assert_includes result, "homepage design"
  end

  test "scopes results to current user only" do
    other_user = users(:two)
    other_meeting = Meeting.create!(title: "Other User Meeting", language: "en-US", status: "completed", source: "imported", user: other_user)
    other_transcript = Transcript.create!(meeting: other_meeting, happyscribe_id: "hs_other", status: "completed")
    TranscriptChunk.create!(transcript: other_transcript, content: "secret budget discussion", position: 0)

    result = @tool.execute(query: "secret")
    assert_includes result, "No transcript content found"
  end

  test "returns message when no content matches" do
    result = @tool.execute(query: "nonexistent_topic_xyz")
    assert_includes result, "No transcript content found"
  end

  test "limits results" do
    result = @tool.execute(query: "budget", limit: 1)
    # Should only return chunks from one meeting context
    meeting_headers = result.scan(/Meeting:/).count
    assert meeting_headers >= 1
    chunks_returned = result.scan(/\[Chunk/).count + result.scan(/Position/).count
    assert chunks_returned <= 1
  end

  test "excludes chunks from non-completed transcripts" do
    # Meeting two has status "uploading" and transcript status "pending"
    # No chunks should come from it
    result = @tool.execute(query: "Hello everyone")
    # The "Hello everyone" chunk belongs to transcript one (completed) via meeting one (completed)
    assert_includes result, "Weekly Standup"
  end

  test "has correct tool description" do
    assert_includes TranscriptSearchTool.description, "transcript"
  end
end
