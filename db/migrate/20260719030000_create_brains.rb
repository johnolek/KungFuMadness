class CreateBrains < ActiveRecord::Migration[8.1]
  def change
    create_table :brains do |t|
      t.string :name, null: false
      t.integer :version, null: false
      t.jsonb :feature_mask, null: false, default: []
      t.jsonb :weights, null: false, default: {}
      t.jsonb :training_meta, null: false, default: {}

      t.timestamps
    end

    add_index :brains, [ :name, :version ], unique: true
  end
end
