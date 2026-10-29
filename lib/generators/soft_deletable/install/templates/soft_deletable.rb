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

  # Whether `dependent: :restrict_with_exception` and `dependent: :restrict_with_error` associations
  # allow soft-deletion despite non-deleted associated records (hard-deletion is always restricted).
  # Can be overridden per association with the `skip_restriction_on_soft_delete:` option.
  # Defaults to `false`.
  #
  # config.skip_restriction_on_soft_delete = false
end
