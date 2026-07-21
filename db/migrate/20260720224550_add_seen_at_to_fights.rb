class AddSeenAtToFights < ActiveRecord::Migration[8.1]
  def change
    add_column :fights, :challenger_seen_at, :datetime
    add_column :fights, :opponent_seen_at, :datetime
  end
end
