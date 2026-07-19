class CreateFightMoves < ActiveRecord::Migration[8.1]
  def change
    create_table :fight_moves do |t|
      t.references :fight, null: false, foreign_key: true
      t.references :fighter, null: false, foreign_key: true
      t.integer :round, null: false
      t.integer :attack_height, null: false
      t.integer :attack_style, null: false
      t.integer :block_height, null: false

      t.timestamps
    end

    add_index :fight_moves, [ :fight_id, :fighter_id, :round ], unique: true
  end
end
