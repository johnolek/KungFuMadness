class AddHideFightSpoilersToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :hide_fight_spoilers, :boolean, default: true, null: false
  end
end
