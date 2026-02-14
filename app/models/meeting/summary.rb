class Meeting::Summary < ApplicationRecord
  belongs_to :meeting
  has_rich_text :content
end
