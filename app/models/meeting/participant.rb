class Meeting::Participant < ApplicationRecord
  belongs_to :meeting
  belongs_to :contact

  validates :contact_id, uniqueness: { scope: :meeting_id }

  enum :role, {
    attendee: "attendee",
    organizer: "organizer"
  }, default: :attendee

  def segments
    return TranscriptSegment.none if speaker_label.blank?

    transcript = meeting.transcript
    return TranscriptSegment.none if transcript.nil?

    transcript.transcript_segments.where(speaker: speaker_label).ordered
  end
end
