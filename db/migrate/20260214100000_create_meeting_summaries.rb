class CreateMeetingSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_summaries do |t|
      t.references :meeting, null: false, foreign_key: true, index: { unique: true }
      t.string :model_used
      t.timestamps
    end
  end
end
