# typed: true
# frozen_string_literal: true

module SoftDeletable
  # Default job for handling `dependent: :destroy_async` associations.
  #
  # @see SoftDeletable.soft_delete_async_job
  class SoftDeleteAsyncJob < ApplicationJob
    queue_as SoftDeletable.config.delete_job_queue

    #: (
    #|   String model_name,
    #|   Array[Integer | String] ids,
    #|   ?deleted_by: ActiveRecord::Base?,
    #|   ?deleted_in: String?,
    #|   ?permanent: bool
    #| ) -> void
    def perform(model_name, ids, deleted_by: nil, deleted_in: nil, permanent: false)
      model = model_name.constantize
      deleted_in ||= SecureRandom.uuid

      last_error = nil

      model.where(id: ids).find_each do |record|
        record.destroy(deleted_by:, deleted_in:, permanent:)
      rescue StandardError => error
        last_error = error
      end

      raise last_error if last_error.present?
    end
  end
end
