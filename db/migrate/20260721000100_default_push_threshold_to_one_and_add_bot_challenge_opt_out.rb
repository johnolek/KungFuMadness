class DefaultPushThresholdToOneAndAddBotChallengeOptOut < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :push_min_pending_challenges, from: 3, to: 1
    up_only { execute("UPDATE users SET push_min_pending_challenges = 1 WHERE push_min_pending_challenges = 3") }
    add_column :users, :allow_bot_challenges, :boolean, default: true, null: false
  end
end
