class CreateTranscripts < ActiveRecord::Migration[8.1]
  def change
    create_table :transcripts do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :happyscribe_id
      t.string :happyscribe_export_id
      t.jsonb :raw_response
      t.string :status, null: false, default: "pending"
      t.integer :audio_length_seconds

      t.timestamps
    end

    add_index :transcripts, :happyscribe_id, unique: true
    add_index :transcripts, :status
  end
end
