class AddMeetingToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :meeting, foreign_key: true
  end
end
