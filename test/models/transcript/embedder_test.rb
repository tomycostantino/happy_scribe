require "test_helper"

class Transcript::EmbedderTest < ActiveSupport::TestCase
  setup do
    @meeting = meetings(:one)
    @transcript = transcripts(:one)
    @transcript.transcript_chunks.delete_all
  end

  test "generates chunks for completed transcript" do
    Transcript::Embedder.perform_now(@meeting.id)

    assert @transcript.transcript_chunks.reload.any?, "Expected transcript chunks to be created"
    @transcript.transcript_chunks.each do |chunk|
      assert chunk.content.present?, "Chunk content should be present"
      assert chunk.position.present?, "Chunk position should be present"
    end
  end

  test "clears existing chunks before generating new ones" do
    @transcript.transcript_chunks.create!(content: "Old chunk", position: 0)
    assert_equal 1, @transcript.transcript_chunks.count

    Transcript::Embedder.perform_now(@meeting.id)

    @transcript.transcript_chunks.reload
    assert @transcript.transcript_chunks.none? { |c| c.content == "Old chunk" }
  end

  test "does nothing for non-completed transcript" do
    @transcript.update!(status: :processing)

    Transcript::Embedder.perform_now(@meeting.id)

    assert_equal 0, @transcript.transcript_chunks.reload.count
  end

  test "does not raise on failure" do
    Transcript::Chunker.stub(:perform_now, ->(_) { raise StandardError, "chunking error" }) do
      assert_nothing_raised do
        Transcript::Embedder.perform_now(@meeting.id)
      end
    end
  end

  test "chunks have content matching transcript segments" do
    Transcript::Embedder.perform_now(@meeting.id)

    all_content = @transcript.transcript_chunks.reload.map(&:content).join(" ")
    assert_includes all_content, "Hello everyone, welcome to the weekly standup."
    assert_includes all_content, "API integration is done"
  end
end
