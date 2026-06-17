class AddCompanyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :company_id, :bigint
    add_foreign_key :users, :companies, validate: false
  end
end
