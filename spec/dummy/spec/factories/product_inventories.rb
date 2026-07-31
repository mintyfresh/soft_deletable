# frozen_string_literal: true

# == Schema Information
#
# Table name: product_inventories
#
#  id            :integer          not null, primary key
#  product_id    :integer          not null
#  quantity      :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  deleted_at    :datetime
#  deleted_in    :string
#  deleted_by_id :integer
#
# Indexes
#
#  index_product_inventories_on_deleted_by_id  (deleted_by_id)
#  index_product_inventories_on_product_id     (product_id) UNIQUE
#
# Foreign Keys
#
#  deleted_by_id  (deleted_by_id => users.id)
#  product_id     (product_id => products.id)
#
FactoryBot.define do
  factory :product_inventory do
    product

    quantity { Faker::Number.between(from: 0, to: 100) }

    trait :deleted do
      deleted { true }
    end
  end
end
