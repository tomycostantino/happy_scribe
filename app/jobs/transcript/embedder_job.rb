class Transcript::EmbedderJob < ApplicationJob
  queue_as :llm

  def perform(meeting_id)
    Transcript::Embedder.perform_now(meeting_id)
  end
end
