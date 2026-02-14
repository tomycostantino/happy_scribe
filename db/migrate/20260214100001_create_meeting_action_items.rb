class CreateMeetingActionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_action_items do |t|
      t.references :meeting, null: false, foreign_key: true
      t.text :description, null: false
      t.string :assignee
      t.date :due_date
      t.boolean :completed, null: false, default: false
      t.timestamps
    end
    add_index :meeting_action_items, [ :meeting_id, :completed ]
  end
end
