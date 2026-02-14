class CreateFollowUpEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :follow_up_emails do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :recipients, null: false
      t.string :subject, null: false
      t.datetime :sent_at

      t.timestamps
    end
  end
end
