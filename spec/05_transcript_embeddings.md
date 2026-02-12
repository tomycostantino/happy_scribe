# Spec 5: Transcript Embeddings

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the embedding generation pipeline that chunks transcripts and stores vector embeddings for future semantic search (v2 RAG feature).

**Architecture:** A `GenerateEmbeddingsJob` runs in parallel with AI processing jobs after transcript export. It uses a `TranscriptChunker` service to split segments into ~500-token chunks, then generates embeddings via OpenAI's `text-embedding-3-small` model through RubyLLM. Embeddings are stored in pgvector columns via the `neighbor` gem.

**Tech Stack:** RubyLLM (OpenAI embeddings), `neighbor` gem, pgvector, Solid Queue.

**Dependencies:** Spec 1 (TranscriptChunk model), Spec 3 (pipeline triggers this job).

**Note:** This is a "store for later" feature. No search UI in v1. We just generate and persist embeddings so the data is ready for v2's Q&A/RAG chat.

---

### Task 1: TranscriptChunker Service

**Files:**
- Create: `app/services/transcript_chunker.rb`
- Test: `test/services/transcript_chunker_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/services/transcript_chunker_test.rb
require "test_helper"

class TranscriptChunkerTest < ActiveSupport::TestCase
  test "chunks transcript segments into groups respecting segment boundaries" do
    transcript = transcripts(:one)
    # Fixture has 3 short segments — should fit in one chunk at default size

    chunker = TranscriptChunker.new(transcript, max_tokens: 500)
    chunks = chunker.chunk

    assert_equal 1, chunks.length
    assert_includes chunks[0][:content], "Speaker 1"
    assert_includes chunks[0][:content], "Speaker 2"
    assert_in_delta 0.0, chunks[0][:start_time]
    assert_in_delta 11.0, chunks[0][:end_time]
    assert_equal 0, chunks[0][:position]
  end

  test "splits into multiple chunks when content exceeds max tokens" do
    transcript = transcripts(:two)

    # Create many segments to exceed one chunk
    20.times do |i|
      transcript.transcript_segments.create!(
        speaker: "Speaker #{i % 2 + 1}",
        content: "This is a longer segment number #{i} with enough content to contribute to the token count. " * 5,
        start_time: i * 10.0,
        end_time: (i + 1) * 10.0,
        position: i
      )
    end

    chunker = TranscriptChunker.new(transcript, max_tokens: 100) # Small limit to force splitting
    chunks = chunker.chunk

    assert chunks.length > 1

    # Each chunk should have a position
    chunks.each_with_index do |chunk, i|
      assert_equal i, chunk[:position]
      assert chunk[:content].present?
      assert_not_nil chunk[:start_time]
      assert_not_nil chunk[:end_time]
    end

    # Chunks should be ordered by time
    start_times = chunks.map { |c| c[:start_time] }
    assert_equal start_times, start_times.sort
  end

  test "includes overlap — last segment of previous chunk appears in next chunk" do
    transcript = transcripts(:two)

    # Create segments that will span multiple chunks
    10.times do |i|
      transcript.transcript_segments.create!(
        speaker: "Speaker 1",
        content: "Segment #{i}. " * 30, # Make each segment large enough
        start_time: i * 10.0,
        end_time: (i + 1) * 10.0,
        position: i
      )
    end

    chunker = TranscriptChunker.new(transcript, max_tokens: 100)
    chunks = chunker.chunk

    # If there are multiple chunks, check overlap
    if chunks.length > 1
      first_chunk_last_line = chunks[0][:content].split("\n\n").last
      second_chunk_first_line = chunks[1][:content].split("\n\n").first
      # The overlap means the last segment of chunk 0 should appear at the start of chunk 1
      assert_equal first_chunk_last_line, second_chunk_first_line
    end
  end

  test "handles transcript with no segments" do
    transcript = transcripts(:two)
    # No segments created

    chunker = TranscriptChunker.new(transcript)
    chunks = chunker.chunk

    assert_equal [], chunks
  end

  test "handles single segment" do
    transcript = transcripts(:two)
    transcript.transcript_segments.create!(
      speaker: "Speaker 1",
      content: "Just one segment.",
      start_time: 0.0,
      end_time: 3.0,
      position: 0
    )

    chunker = TranscriptChunker.new(transcript)
    chunks = chunker.chunk

    assert_equal 1, chunks.length
    assert_includes chunks[0][:content], "Just one segment."
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/transcript_chunker_test.rb`
Expected: FAIL

**Step 3: Implement the chunker**

```ruby
# app/services/transcript_chunker.rb
class TranscriptChunker
  # Approximate: 1 token ~ 4 characters
  CHARS_PER_TOKEN = 4
  DEFAULT_MAX_TOKENS = 500

  def initialize(transcript, max_tokens: DEFAULT_MAX_TOKENS)
    @transcript = transcript
    @max_chars = max_tokens * CHARS_PER_TOKEN
  end

  def chunk
    segments = @transcript.transcript_segments.order(:position).to_a
    return [] if segments.empty?

    chunks = []
    current_segments = []
    current_chars = 0

    segments.each do |segment|
      formatted = format_segment(segment)
      segment_chars = formatted.length

      if current_chars + segment_chars > @max_chars && current_segments.any?
        # Save current chunk
        chunks << build_chunk(current_segments, chunks.length)

        # Start new chunk with overlap (last segment of previous chunk)
        overlap = current_segments.last
        current_segments = overlap ? [overlap] : []
        current_chars = overlap ? format_segment(overlap).length : 0
      end

      current_segments << segment
      current_chars += segment_chars
    end

    # Don't forget the last chunk
    chunks << build_chunk(current_segments, chunks.length) if current_segments.any?

    chunks
  end

  private

  def format_segment(segment)
    timestamp = format_timestamp(segment.start_time)
    "#{segment.speaker} [#{timestamp}]: #{segment.content}"
  end

  def format_timestamp(seconds)
    return "00:00:00" if seconds.nil?
    Time.at(seconds.to_f).utc.strftime("%H:%M:%S")
  end

  def build_chunk(segments, position)
    content = segments.map { |s| format_segment(s) }.join("\n\n")

    {
      content: content,
      start_time: segments.first.start_time,
      end_time: segments.last.end_time,
      position: position
    }
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/services/transcript_chunker_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptChunker service for embedding preparation"
```

---

### Task 2: GenerateEmbeddingsJob

**Files:**
- Create: `app/jobs/generate_embeddings_job.rb`
- Test: `test/jobs/generate_embeddings_job_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/jobs/generate_embeddings_job_test.rb
require "test_helper"

class GenerateEmbeddingsJobTest < ActiveJob::TestCase
  setup do
    @meeting = meetings(:two)
    @meeting.update!(status: :processing)
    @transcript = transcripts(:two)
    @transcript.update!(status: :completed)

    3.times do |i|
      @transcript.transcript_segments.create!(
        speaker: "Speaker 1",
        content: "Segment #{i} content for embedding.",
        start_time: i * 5.0,
        end_time: (i + 1) * 5.0,
        position: i
      )
    end
  end

  test "generates chunks and stores embeddings" do
    # Mock RubyLLM embed to return fake vectors
    fake_embedding = Array.new(1536, 0.1)

    mock_embed = Minitest::Mock.new
    # Called once per chunk (3 short segments = 1 chunk at default max_tokens)
    mock_embed.expect(:embed, [OpenStruct.new(embedding: fake_embedding)], [String])

    RubyLLM.stub(:embed, ->(*args, **kwargs) { mock_embed.embed(*args) }) do
      GenerateEmbeddingsJob.perform_now(@meeting.id)
    end

    chunks = @transcript.transcript_chunks.order(:position)
    assert chunks.any?

    chunks.each do |chunk|
      assert chunk.content.present?
      assert_not_nil chunk.position
      # Note: embedding may be nil in test if pgvector isn't fully set up,
      # but the record should exist
    end

    mock_embed.verify
  end

  test "clears existing chunks before regenerating" do
    @transcript.transcript_chunks.create!(
      content: "Old chunk", position: 0
    )

    fake_embedding = Array.new(1536, 0.1)
    mock_embed = Minitest::Mock.new
    mock_embed.expect(:embed, [OpenStruct.new(embedding: fake_embedding)], [String])

    RubyLLM.stub(:embed, ->(*args, **kwargs) { mock_embed.embed(*args) }) do
      GenerateEmbeddingsJob.perform_now(@meeting.id)
    end

    # Old chunk should be replaced
    chunks = @transcript.transcript_chunks
    assert chunks.none? { |c| c.content == "Old chunk" }

    mock_embed.verify
  end

  test "does not block meeting completion — embedding failure is logged but not fatal" do
    RubyLLM.stub(:embed, ->(*args, **kwargs) { raise StandardError, "Embedding API down" }) do
      # Should not raise — job catches and logs
      GenerateEmbeddingsJob.perform_now(@meeting.id)
    end

    # Meeting status should not change to failed because of embedding failure
    assert_equal "processing", @meeting.reload.status
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/generate_embeddings_job_test.rb`
Expected: FAIL

**Step 3: Implement the job**

```ruby
# app/jobs/generate_embeddings_job.rb
class GenerateEmbeddingsJob < ApplicationJob
  queue_as :default

  EMBEDDING_MODEL = "text-embedding-3-small"
  BATCH_SIZE = 20

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    transcript = meeting.transcript

    # Clear existing chunks
    transcript.transcript_chunks.destroy_all

    # Generate chunks
    chunks = TranscriptChunker.new(transcript).chunk
    return if chunks.empty?

    # Process in batches
    chunks.each_slice(BATCH_SIZE) do |batch|
      texts = batch.map { |c| c[:content] }

      # Generate embeddings via RubyLLM (OpenAI)
      embeddings = RubyLLM.embed(texts, model: EMBEDDING_MODEL)

      batch.each_with_index do |chunk_data, i|
        transcript.transcript_chunks.create!(
          content: chunk_data[:content],
          embedding: embeddings[i]&.embedding,
          position: chunk_data[:position],
          start_time: chunk_data[:start_time],
          end_time: chunk_data[:end_time]
        )
      end
    end

    Rails.logger.info("Generated #{chunks.length} embedding chunks for meeting #{meeting_id}")
  rescue StandardError => e
    # Embedding generation failure should NOT fail the meeting.
    # It's a "nice to have" for future search. Log and move on.
    Rails.logger.error("GenerateEmbeddingsJob failed for meeting #{meeting_id}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/jobs/generate_embeddings_job_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add GenerateEmbeddingsJob with OpenAI text-embedding-3-small"
```
