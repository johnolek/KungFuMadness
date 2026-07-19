class CreateFights < ActiveRecord::Migration[8.1]
  def change
    create_table :fights do |t|
      t.references :challenger, null: false, foreign_key: { to_table: :fighters }
      t.references :opponent, null: false, foreign_key: { to_table: :fighters }
      t.integer :status, null: false, default: 0

      t.integer :challenger_belt, null: false
      t.integer :challenger_xp, null: false
      t.integer :opponent_belt, null: false
      t.integer :opponent_xp, null: false

      t.references :winner, foreign_key: { to_table: :fighters }
      t.boolean :ko, null: false, default: false
      t.integer :challenger_xp_delta
      t.integer :opponent_xp_delta

      t.datetime :expires_at, null: false
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :fights, [ :opponent_id, :status ]
    add_index :fights, [ :challenger_id, :status ]
    add_index :fights, [ :status, :expires_at ]
    add_index :fights, :resolved_at
  end
end
