# frozen_string_literal: true

module Inventoriable
  extend ActiveSupport::Concern

  included do
    has_one :inventory, class_name: 'ProductInventory', dependent: :destroy, inverse_of: :product
  end
end
