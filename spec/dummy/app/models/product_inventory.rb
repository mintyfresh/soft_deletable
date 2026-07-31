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
class ProductInventory < ApplicationRecord
  include SoftDeletable::Model

  belongs_to :product, inverse_of: :inventory

  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
