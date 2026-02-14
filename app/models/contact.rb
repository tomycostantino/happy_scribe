class Contact < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { scope: :user_id }

  normalizes :email, with: ->(e) { e.strip.downcase }

  scope :search_by_name, ->(name) { where("name ILIKE ?", "%#{sanitize_sql_like(name)}%") }
end
