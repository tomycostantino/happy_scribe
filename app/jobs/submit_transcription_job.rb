class SubmitTranscriptionJob < ApplicationJob
  queue_as :default

  retry_on HappyScribe::RateLimitError, wait: :polynomially_longer, attempts: 5

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    transcript = meeting.transcript
    client = HappyScribe::Client.new

    # 1. Get signed upload URL
    filename = meeting.recording.filename.to_s
    signed_url = client.get_signed_upload_url(filename: filename)["signedUrl"]

    # 2. Upload file to S3
    client.upload_to_signed_url(
      signed_url: signed_url,
      file_data: meeting.recording.download,
      content_type: meeting.recording.content_type
    )

    # 3. Create transcription on HappyScribe
    result = client.create_transcription(
      name: meeting.title,
      language: meeting.language,
      tmp_url: signed_url
    )

    # 4. Update local records
    transcript.update!(happyscribe_id: result["id"], status: :processing)
    meeting.update!(status: :transcribing)

    # 5. Start polling
    PollTranscriptionJob.perform_later(meeting.id)
  rescue HappyScribe::RateLimitError
    raise # Let retry_on handle it
  rescue => e
    Meeting.find(meeting_id).update!(status: :failed)
    Rails.logger.error("SubmitTranscriptionJob failed for meeting #{meeting_id}: #{e.message}")
  end
end
