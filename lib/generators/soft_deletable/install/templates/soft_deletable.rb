# frozen_string_literal: true

SoftDeletable.configure do |config|
  # When using `dependent: :destroy_async` associations,
  # this is the queue that will be used by the `SoftDeletable::SoftDeleteAsyncJob`.
  # Defaults to `:default`.
  #
  # config.delete_job_queue = :default

  # When using `dependent: :destroy_async` associations,
  # this is the queue that will be used by the `SoftDeletable::RestoreAsyncJob`.
  # Defaults to `:default`.
  #
  # config.restore_job_queue = :default

  # The class name of the user model used by the `belongs_to :deleted_by` association.
  # Defaults to `'User'`.
  #
  # config.user_class_name = 'User'
end
