class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :last_name, null: false
      t.string :first_name, null: false
      t.string :middle_name
      t.date :birth_date, null: false
      t.string :gender, null: false
      t.bigint :mother_id
      t.bigint :father_id

      t.timestamps
    end

    add_foreign_key :users, :users, column: :mother_id, validate: false
    add_foreign_key :users, :users, column: :father_id, validate: false
  end
end
