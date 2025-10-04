# frozen_string_literal: true

class CreateProductVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :product_variants do |t|
      t.belongs_to :product, null: false, foreign_key: true
      t.string     :name, null: false
      t.integer    :price_cents, null: false
      t.timestamps
      t.soft_deletable
    end
  end
end
