# frozen_string_literal: true

# == Schema Information
#
# Table name: product_variants
#
#  id            :integer          not null, primary key
#  product_id    :integer          not null
#  name          :string           not null
#  price_cents   :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  deleted_at    :datetime
#  deleted_in    :string
#  deleted_by_id :integer
#
# Indexes
#
#  index_product_variants_on_deleted_by_id  (deleted_by_id)
#  index_product_variants_on_product_id     (product_id)
#
# Foreign Keys
#
#  deleted_by_id  (deleted_by_id => users.id)
#  product_id     (product_id => products.id)
#
FactoryBot.define do
  factory :product_variant do
    product

    name { Faker::Commerce.product_name }
    price_cents { Faker::Number.between(from: 100, to: 10_000) }

    trait :deleted do
      deleted { true }
    end
  end
end
