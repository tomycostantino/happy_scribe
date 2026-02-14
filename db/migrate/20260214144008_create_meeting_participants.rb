class CreateMeetingParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_participants do |t|
      t.references :meeting, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :role, default: "attendee"
      t.string :speaker_label

      t.timestamps
    end

    add_index :meeting_participants, [ :meeting_id, :contact_id ], unique: true
  end
end
