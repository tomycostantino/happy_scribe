module Meeting::Recordable
  extend ActiveSupport::Concern

  included do
    has_one_attached :recording

    validate :recording_attached
  end

  private

  def recording_attached
    errors.add(:recording, "must be attached") unless recording.attached?
  end
end
