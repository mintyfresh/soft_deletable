# frozen_string_literal: true

class CreateTags < ActiveRecord::Migration[8.0]
  def change
    create_table :tags do |t|
      t.string :name, null: false
      t.timestamps
      t.soft_deletable
    end

    create_join_table :products, :tags do |t|
      t.index %i[product_id tag_id], unique: true
      t.index :tag_id
    end
  end
end
