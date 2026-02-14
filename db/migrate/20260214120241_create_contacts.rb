class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.text :notes

      t.timestamps
    end

    add_index :contacts, [ :user_id, :email ], unique: true
    add_index :contacts, [ :user_id, :name ]
  end
end
