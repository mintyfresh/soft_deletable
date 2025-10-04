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
class User < ApplicationRecord
  include SoftDeletable::Model

  has_many :created_products, class_name: 'Product', dependent: :destroy_async,
                              inverse_of: :created_by, foreign_key: :created_by_id

  validates :email, presence: true, uniqueness: true
end
