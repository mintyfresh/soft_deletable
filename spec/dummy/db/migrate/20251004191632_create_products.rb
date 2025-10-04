# frozen_string_literal: true

class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.belongs_to :created_by, null: false, foreign_key: { to_table: :users }
      t.string  :name, null: false
      t.integer :price_cents, null: false
      t.timestamps
    end

    add_soft_deletable :products
  end
end
