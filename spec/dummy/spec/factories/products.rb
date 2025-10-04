# frozen_string_literal: true

# == Schema Information
#
# Table name: products
#
#  id            :integer          not null, primary key
#  created_by_id :integer          not null
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
#  index_products_on_created_by_id  (created_by_id)
#  index_products_on_deleted_by_id  (deleted_by_id)
#
# Foreign Keys
#
#  created_by_id  (created_by_id => users.id)
#  deleted_by_id  (deleted_by_id => users.id)
#
FactoryBot.define do
  factory :product do
    created_by factory: :user

    name { Faker::Commerce.product_name }
    price_cents { Faker::Number.between(from: 100, to: 10_000) }

    trait :deleted do
      deleted_at { Time.current }
      deleted_in { SecureRandom.uuid }
      deleted_by { build(:user) }
    end

    trait :with_variants do
      transient do
        variants_count { 3 }
      end

      variants do
        build_list(:product_variant, variants_count, product: instance, deleted_at:, deleted_in:, deleted_by:)
      end
    end
  end
end
