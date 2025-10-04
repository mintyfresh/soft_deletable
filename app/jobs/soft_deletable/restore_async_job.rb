# frozen_string_literal: true

module SoftDeletable
  # Default job for handling `dependent: :destroy_async` associations.
  #
  # @see SoftDeletable.restore_async_job
  class RestoreAsyncJob < ApplicationJob
    queue_as SoftDeletable.config.restore_job_queue

    # @param model_name [String]
    # @param ids [Array<Integer, String>]
    def perform(model_name, ids)
      model = model_name.constantize

      last_error = nil

      model.where(id: ids).find_each do |record|
        record.restore
      rescue StandardError => error
        last_error = error
      end

      raise last_error if last_error.present?
    end
  end
end
