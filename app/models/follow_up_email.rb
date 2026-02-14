class FollowUpEmail < ApplicationRecord
  belongs_to :meeting
  has_rich_text :body

  validates :recipients, presence: true
  validates :subject, presence: true
  validates :body, presence: true

  scope :sent, -> { where.not(sent_at: nil) }

  def recipient_list
    recipients.split(",").map(&:strip)
  end

  def sent?
    sent_at.present?
  end
end
