class Contact < ApplicationRecord
  include Broadcastable

  belongs_to :user

  has_many :meeting_participants, class_name: "Meeting::Participant", dependent: :destroy
  has_many :meetings, through: :meeting_participants

  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { scope: :user_id }

  normalizes :email, with: ->(e) { e.strip.downcase }

  scope :search_by_name, ->(name) { where("name ILIKE ?", "%#{sanitize_sql_like(name)}%") }

  def sent_emails
    FollowUpEmail.sent
      .joins(:meeting)
      .where(meetings: { user_id: user_id })
      .where("recipients ILIKE ?", "%#{FollowUpEmail.sanitize_sql_like(email)}%")
      .order(sent_at: :desc)
  end
end
