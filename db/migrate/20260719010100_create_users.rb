class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.citext :username, null: false
      t.string :email
      t.string :webauthn_id, null: false
      t.datetime :email_verified_at

      t.timestamps
    end

    add_index :users, :username, unique: true
    add_index :users, :webauthn_id, unique: true
    add_index :users, "lower(email)", unique: true, where: "email IS NOT NULL",
                                       name: "index_users_on_lower_email"
  end
end
