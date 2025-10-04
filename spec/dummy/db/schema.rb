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

ActiveRecord::Schema[8.0].define(version: 2025_10_04_191645) do
  create_table "product_variants", force: :cascade do |t|
    t.integer "product_id", null: false
    t.string "name", null: false
    t.integer "price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.string "deleted_in"
    t.integer "deleted_by_id"
    t.index ["deleted_by_id"], name: "index_product_variants_on_deleted_by_id"
    t.index ["product_id"], name: "index_product_variants_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.integer "created_by_id", null: false
    t.string "name", null: false
    t.integer "price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.string "deleted_in"
    t.integer "deleted_by_id"
    t.index ["created_by_id"], name: "index_products_on_created_by_id"
    t.index ["deleted_by_id"], name: "index_products_on_deleted_by_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.string "deleted_in"
    t.integer "deleted_by_id"
    t.index ["deleted_by_id"], name: "index_users_on_deleted_by_id"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "product_variants", "products"
  add_foreign_key "product_variants", "users", column: "deleted_by_id"
  add_foreign_key "products", "users", column: "created_by_id"
  add_foreign_key "products", "users", column: "deleted_by_id"
  add_foreign_key "users", "users", column: "deleted_by_id"
end
