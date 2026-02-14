require "test_helper"

class TranscriptChunkTest < ActiveSupport::TestCase
  test "valid chunk" do
    chunk = TranscriptChunk.new(transcript: transcripts(:one), content: "Speaker 1: Hello.", position: 0)
    assert chunk.valid?
  end

  test "requires content" do
    chunk = TranscriptChunk.new(transcript: transcripts(:one), position: 0)
    assert_not chunk.valid?
    assert_includes chunk.errors[:content], "can't be blank"
  end

  test "requires position" do
    chunk = TranscriptChunk.new(transcript: transcripts(:one), content: "Some text")
    assert_not chunk.valid?
    assert_includes chunk.errors[:position], "can't be blank"
  end

  test "requires a transcript" do
    chunk = TranscriptChunk.new(content: "Some text", position: 0)
    assert_not chunk.valid?
  end

  test "has_neighbors for embedding" do
    assert TranscriptChunk.method_defined?(:nearest_neighbors)
  end
end
