class CreateMeetings < ActiveRecord::Migration[8.1]
  def change
    create_table :meetings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :language, null: false, default: "en-US"
      t.string :status, null: false, default: "uploading"
      t.string :google_calendar_event_id

      t.timestamps
    end

    add_index :meetings, :status
    add_index :meetings, [ :user_id, :created_at ]
  end
end
