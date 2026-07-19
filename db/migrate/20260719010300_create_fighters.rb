class CreateFighters < ActiveRecord::Migration[8.1]
  def change
    create_table :fighters do |t|
      t.references :user, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.integer :xp, null: false, default: 0
      t.integer :belt, null: false, default: 1
      t.integer :wins, null: false, default: 0
      t.integer :losses, null: false, default: 0
      t.integer :draws, null: false, default: 0
      t.integer :declines, null: false, default: 0
      t.boolean :bot, null: false, default: false
      t.jsonb :strategy, null: false, default: {}
      t.datetime :last_seen_at
      t.datetime :last_fought_at

      t.timestamps
    end

    add_index :fighters, "lower(name)", unique: true, name: "index_fighters_on_lower_name"
    add_index :fighters, :belt
    add_index :fighters, :last_seen_at
  end
end
