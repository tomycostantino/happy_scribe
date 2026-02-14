class Meeting::ActionItem < ApplicationRecord
  include Broadcastable

  belongs_to :meeting
  validates :description, presence: true
  scope :pending, -> { where(completed: false) }
  scope :done, -> { where(completed: true) }
end
