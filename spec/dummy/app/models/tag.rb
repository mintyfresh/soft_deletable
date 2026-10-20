# frozen_string_literal: true

# == Schema Information
#
# Table name: tags
#
#  id            :integer          not null, primary key
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  deleted_at    :datetime
#  deleted_in    :string
#  deleted_by_id :integer
#
# Indexes
#
#  index_tags_on_deleted_by_id  (deleted_by_id)
#
# Foreign Keys
#
#  deleted_by_id  (deleted_by_id => users.id)
#
class Tag < ApplicationRecord
  include SoftDeletable::Model

  has_and_belongs_to_many :products

  validates :name, presence: true
end
