class CreateFightRounds < ActiveRecord::Migration[8.1]
  def change
    create_table :fight_rounds do |t|
      t.references :fight, null: false, foreign_key: true
      t.integer :round, null: false
      t.integer :challenger_damage, null: false
      t.integer :opponent_damage, null: false
      t.integer :challenger_hp_after, null: false
      t.integer :opponent_hp_after, null: false

      t.timestamps
    end

    add_index :fight_rounds, [ :fight_id, :round ], unique: true
  end
end
