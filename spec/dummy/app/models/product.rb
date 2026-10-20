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
class Product < ApplicationRecord
  include Inventoriable
  include SoftDeletable::Model

  belongs_to :created_by, class_name: 'User', inverse_of: :created_products

  has_many :variants, class_name: 'ProductVariant', dependent: :destroy, inverse_of: :product
  has_many :all_variants, class_name: 'ProductVariant', includes_deleted: :always, inverse_of: false, dependent: nil
  has_many :live_variants, class_name: 'ProductVariant', includes_deleted: :never, inverse_of: false, dependent: nil

  has_and_belongs_to_many :tags

  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0 }
end
