class AddPushMinPendingChallengesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :push_min_pending_challenges, :integer, default: 3, null: false
  end
end
