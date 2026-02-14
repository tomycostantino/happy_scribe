require "test_helper"

class Transcript::ChunkerTest < ActiveSupport::TestCase
  setup do
    @transcript = transcripts(:one)
  end

  test "chunks a transcript into segments" do
    chunks = Transcript::Chunker.perform_now(@transcript)
    assert chunks.any?
    assert_kind_of Array, chunks
  end

  test "each chunk has required keys" do
    chunks = Transcript::Chunker.perform_now(@transcript)
    chunks.each do |chunk|
      assert chunk.key?(:content), "Missing :content key"
      assert chunk.key?(:start_time), "Missing :start_time key"
      assert chunk.key?(:end_time), "Missing :end_time key"
      assert chunk.key?(:position), "Missing :position key"
    end
  end

  test "chunks have sequential positions" do
    chunks = Transcript::Chunker.perform_now(@transcript)
    assert_equal (0...chunks.size).to_a, chunks.map { |c| c[:position] }
  end

  test "chunks use Speaker [HH:MM:SS]: format" do
    chunks = Transcript::Chunker.perform_now(@transcript)
    assert_match(/Speaker \d+ \[\d{2}:\d{2}:\d{2}\]:/, chunks.first[:content])
  end

  test "returns empty array for transcript with no segments" do
    transcript = transcripts(:two)
    chunks = Transcript::Chunker.perform_now(transcript)
    assert_equal [], chunks
  end

  test "respects max_tokens by splitting into multiple chunks" do
    # Use a very small max_tokens to force splitting
    # Each segment is ~50 chars, so at 10 tokens (40 chars) each should be its own chunk
    chunks = Transcript::Chunker.perform_now(@transcript, max_tokens: 15)
    assert chunks.size > 1, "Expected multiple chunks with small max_tokens, got #{chunks.size}"
  end

  test "chunks have overlap of last segment" do
    # With tiny max_tokens, consecutive chunks should share content
    chunks = Transcript::Chunker.perform_now(@transcript, max_tokens: 15)
    return if chunks.size < 2

    # The last segment of chunk N should appear at the start of chunk N+1
    first_chunk_lines = chunks[0][:content].split("\n\n")
    second_chunk_lines = chunks[1][:content].split("\n\n")

    last_line_of_first = first_chunk_lines.last
    first_line_of_second = second_chunk_lines.first

    assert_equal last_line_of_first, first_line_of_second,
      "Expected overlap: last segment of chunk 0 should be first segment of chunk 1"
  end

  test "single chunk for transcript that fits within max_tokens" do
    # Default 500 tokens = 2000 chars, which easily fits the 3 short test segments
    chunks = Transcript::Chunker.perform_now(@transcript)
    assert_equal 1, chunks.size
  end

  test "chunk content includes all segments when they fit" do
    chunks = Transcript::Chunker.perform_now(@transcript)
    content = chunks.first[:content]

    assert_includes content, "Hello everyone, welcome to the weekly standup."
    assert_includes content, "the API integration is done"
    assert_includes content, "Let's move on to the next topic."
  end

  test "chunk times span its segments" do
    chunks = Transcript::Chunker.perform_now(@transcript)
    chunk = chunks.first

    assert_in_delta 0.0, chunk[:start_time]
    assert_in_delta 11.0, chunk[:end_time]
  end
end
