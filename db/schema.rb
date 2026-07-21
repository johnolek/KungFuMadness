# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_21_000200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "brains", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "feature_mask", default: [], null: false
    t.string "name", null: false
    t.jsonb "training_meta", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.jsonb "weights", default: {}, null: false
    t.index ["name", "version"], name: "index_brains_on_name_and_version", unique: true
  end

  create_table "credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "nickname"
    t.text "public_key", null: false
    t.integer "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["external_id"], name: "index_credentials_on_external_id", unique: true
    t.index ["user_id"], name: "index_credentials_on_user_id"
  end

  create_table "fight_moves", force: :cascade do |t|
    t.integer "attack_height", null: false
    t.integer "attack_style", null: false
    t.integer "block_height", null: false
    t.datetime "created_at", null: false
    t.bigint "fight_id", null: false
    t.bigint "fighter_id", null: false
    t.integer "round", null: false
    t.datetime "updated_at", null: false
    t.index ["fight_id", "fighter_id", "round"], name: "index_fight_moves_on_fight_id_and_fighter_id_and_round", unique: true
    t.index ["fight_id"], name: "index_fight_moves_on_fight_id"
    t.index ["fighter_id"], name: "index_fight_moves_on_fighter_id"
  end

  create_table "fight_rounds", force: :cascade do |t|
    t.integer "challenger_damage", null: false
    t.integer "challenger_hp_after", null: false
    t.datetime "created_at", null: false
    t.bigint "fight_id", null: false
    t.integer "opponent_damage", null: false
    t.integer "opponent_hp_after", null: false
    t.integer "round", null: false
    t.datetime "updated_at", null: false
    t.index ["fight_id", "round"], name: "index_fight_rounds_on_fight_id_and_round", unique: true
    t.index ["fight_id"], name: "index_fight_rounds_on_fight_id"
  end

  create_table "fighters", force: :cascade do |t|
    t.integer "belt", default: 1, null: false
    t.boolean "bot", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "declines", default: 0, null: false
    t.integer "draws", default: 0, null: false
    t.datetime "last_fought_at"
    t.datetime "last_seen_at"
    t.integer "losses", default: 0, null: false
    t.string "name", null: false
    t.jsonb "strategy", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.integer "wins", default: 0, null: false
    t.integer "xp", default: 0, null: false
    t.index "lower((name)::text)", name: "index_fighters_on_lower_name", unique: true
    t.index ["belt"], name: "index_fighters_on_belt"
    t.index ["last_seen_at"], name: "index_fighters_on_last_seen_at"
    t.index ["user_id"], name: "index_fighters_on_user_id", unique: true
  end

  create_table "fights", force: :cascade do |t|
    t.integer "challenger_belt", null: false
    t.bigint "challenger_id", null: false
    t.datetime "challenger_seen_at"
    t.integer "challenger_xp", null: false
    t.integer "challenger_xp_delta"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.boolean "ko", default: false, null: false
    t.integer "opponent_belt", null: false
    t.bigint "opponent_id", null: false
    t.datetime "opponent_seen_at"
    t.integer "opponent_xp", null: false
    t.integer "opponent_xp_delta"
    t.datetime "resolved_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "winner_id"
    t.index ["challenger_id", "status"], name: "index_fights_on_challenger_id_and_status"
    t.index ["challenger_id"], name: "index_fights_on_challenger_id"
    t.index ["opponent_id", "status"], name: "index_fights_on_opponent_id_and_status"
    t.index ["opponent_id"], name: "index_fights_on_opponent_id"
    t.index ["resolved_at"], name: "index_fights_on_resolved_at"
    t.index ["status", "expires_at"], name: "index_fights_on_status_and_expires_at"
    t.index ["winner_id"], name: "index_fights_on_winner_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "allow_bot_challenges", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "email_verified_at"
    t.boolean "hide_fight_spoilers", default: true, null: false
    t.integer "push_min_pending_challenges", default: 1, null: false
    t.datetime "updated_at", null: false
    t.citext "username", null: false
    t.string "webauthn_id", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["username"], name: "index_users_on_username", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  add_foreign_key "credentials", "users"
  add_foreign_key "fight_moves", "fighters"
  add_foreign_key "fight_moves", "fights"
  add_foreign_key "fight_rounds", "fights"
  add_foreign_key "fighters", "users"
  add_foreign_key "fights", "fighters", column: "challenger_id"
  add_foreign_key "fights", "fighters", column: "opponent_id"
  add_foreign_key "fights", "fighters", column: "winner_id"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
