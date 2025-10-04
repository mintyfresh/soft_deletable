# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id            :integer          not null, primary key
#  email         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  deleted_at    :datetime
#  deleted_in    :string
#  deleted_by_id :integer
#
# Indexes
#
#  index_users_on_deleted_by_id  (deleted_by_id)
#  index_users_on_email          (email) UNIQUE
#
# Foreign Keys
#
#  deleted_by_id  (deleted_by_id => users.id)
#
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| Faker::Internet.email(name: "#{Faker::Internet.username}#{n}") }

    trait :deleted do
      deleted_at { Time.current }
      deleted_in { SecureRandom.uuid }
      deleted_by { build(:user) }
    end

    trait :with_created_products do
      transient do
        created_products_count { 3 }
        created_products_traits { [] }
      end

      created_products do
        build_list(
          :product, created_products_count, *created_products_traits,
          created_by: instance, deleted_at:, deleted_in:, deleted_by:
        )
      end
    end
  end
end
