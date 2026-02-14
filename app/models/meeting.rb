class Meeting < ApplicationRecord
  include Recordable
  include Transcribable
  include Analyzable

  belongs_to :user
  has_one :summary, class_name: "Meeting::Summary", dependent: :destroy
  has_many :action_items, class_name: "Meeting::ActionItem", dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :follow_up_emails, dependent: :destroy
  has_many :participants, class_name: "Meeting::Participant", dependent: :destroy
  has_many :contacts, through: :participants

  enum :status, {
    uploading: "uploading",
    transcribing: "transcribing",
    transcribed: "transcribed",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :uploading

  enum :source, {
    uploaded: "uploaded",
    imported: "imported"
  }, default: :uploaded

  validates :title, presence: true
  validates :language, presence: true

  def check_processing_complete!
    return unless summary.present? && action_items.any?
    update_column(:status, "completed")
  end
end
