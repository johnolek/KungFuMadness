class AddChallengeMessageToFights < ActiveRecord::Migration[8.1]
  def change
    add_column :fights, :challenge_message, :string
  end
end
