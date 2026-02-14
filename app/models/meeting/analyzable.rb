# Orchestrates AI processing after transcription completes.
#
# Enqueues summary generation, action item extraction, and
# transcript chunking jobs in parallel. Only fires when the
# meeting is in the :transcribed state.
module Meeting::Analyzable
  extend ActiveSupport::Concern

  def start_analysis!
    return unless transcribed?

    update_column(:status, "processing")

    Meeting::Summary::GenerateJob.perform_later(id)
    Meeting::ActionItem::ExtractJob.perform_later(id)
    Transcript::EmbedderJob.perform_later(id)
  end
end
