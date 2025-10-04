# frozen_string_literal: true

module SoftDeletable
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
