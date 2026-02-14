class AddSourceToMeetings < ActiveRecord::Migration[8.1]
  def change
    add_column :meetings, :source, :string, default: "uploaded", null: false
  end
end
