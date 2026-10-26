# frozen_string_literal: true

class AddVariantsCountToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :variants_count, :integer, null: false, default: 0
  end
end
