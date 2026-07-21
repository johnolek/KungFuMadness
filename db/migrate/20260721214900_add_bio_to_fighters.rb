class AddBioToFighters < ActiveRecord::Migration[8.1]
  def change
    add_column :fighters, :bio, :string
  end
end
