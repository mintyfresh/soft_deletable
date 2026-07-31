# frozen_string_literal: true

class CreateProductInventories < ActiveRecord::Migration[8.0]
  def change
    create_table :product_inventories do |t|
      t.belongs_to :product, null: false, foreign_key: true, index: { unique: true }
      t.integer    :quantity, null: false
      t.timestamps
      t.soft_deletable
    end
  end
end
