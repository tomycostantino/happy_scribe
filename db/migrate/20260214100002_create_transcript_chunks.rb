class CreateTranscriptChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :transcript_chunks do |t|
      t.references :transcript, null: false, foreign_key: true
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.integer :position, null: false
      t.float :start_time
      t.float :end_time
      t.timestamps
    end
    add_index :transcript_chunks, [ :transcript_id, :position ]
  end
end
