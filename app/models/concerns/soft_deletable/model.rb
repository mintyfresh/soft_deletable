# frozen_string_literal: true

module SoftDeletable
  module Model
    extend ActiveSupport::Concern

    # @scope private
    UNSPECIFIED = Object.new.freeze
    private_constant :UNSPECIFIED

    included do
      define_model_callbacks :soft_delete, :restore
      define_model_callbacks :soft_delete_commit, :restore_commit, only: :after

      belongs_to :deleted_by, class_name: SoftDeletable.config.user_class_name, optional: true

      around_save :run_soft_delete_callbacks, if: -> { deleted_changed?(to: true) }
      around_save :run_restore_callbacks, if: -> { deleted_changed?(to: false) }

      after_commit :run_soft_delete_commit_callbacks, if: -> { saved_change_to_deleted?(to: true) }
      after_commit :run_restore_commit_callbacks, if: -> { saved_change_to_deleted?(to: false) }

      scope :deleted, -> { where.not(deleted_at: nil) }
      scope :not_deleted, -> { where(deleted_at: nil) }
      scope :unscope_deleted, -> { unscope(where: :deleted_at) }
    end

    class_methods do
      # Indicator for soft-deletable models.
      #
      # @return [Boolean]
      def soft_deletable? = true

      # Specifies the job to use for soft-deleting records.
      # Defaults to `SoftDeletable::SoftDeleteAsyncJob`.
      #
      # @return [Class<ActiveJob::Base>]
      def soft_delete_async_job
        SoftDeletable::SoftDeleteAsyncJob
      end

      # Specifies the job to use for restoring soft-deleted records.
      # Defaults to `SoftDeletable::RestoreAsyncJob`.
      #
      # @return [Class<ActiveJob::Base>]
      def restore_async_job
        SoftDeletable::RestoreAsyncJob
      end
    end

    # @return [Boolean]
    def deleted?
      deleted_at.present?
    end

    alias deleted deleted?

    # @param value [Boolean]
    # @return [void]
    def deleted=(value)
      if ActiveRecord::Type::Boolean.new.cast(value)
        self.deleted_at ||= Time.current
      else
        self.deleted_at = nil
      end
    end

    # @return [Boolean]
    def deleted_was # rubocop:disable Naming/PredicateMethod
      deleted_at_was.present?
    end

    # @return [Boolean]
    def deleted_before_last_save # rubocop:disable Naming/PredicateMethod
      deleted_at_before_last_save.present?
    end

    # Checks if the deleted attribute has an unsaved change.
    #
    # @param to [Boolean] an optional value to check against
    # @param from [Boolean] an optional value to check against
    # @return [Boolean]
    def deleted_changed?(to: UNSPECIFIED, from: UNSPECIFIED)
      new_value = deleted
      old_value = deleted_was
      return false if new_value == old_value

      (to == UNSPECIFIED || to == new_value) &&
        (from == UNSPECIFIED || from == old_value)
    end

    # Checks if a change to the deleted attribute has been saved.
    #
    # @param to [Boolean] an optional value to check against
    # @param from [Boolean] an optional value to check against
    # @return [Boolean]
    def saved_change_to_deleted?(to: UNSPECIFIED, from: UNSPECIFIED)
      new_value = deleted
      old_value = deleted_before_last_save
      return false if new_value == old_value

      (to == UNSPECIFIED || to == new_value) &&
        (from == UNSPECIFIED || from == old_value)
    end

    # Marks a record for destruction.
    #
    # @param deleted_in [String]
    # @param deleted_by [User, nil]
    # @return [void]
    def mark_for_destruction(deleted_in: SecureRandom.uuid, deleted_by: nil)
      self.deleted = true
      self.deleted_in = deleted_in
      self.deleted_by = deleted_by
    end

    # Soft-deletes a record.
    #
    # @param deleted_in [String]
    # @param deleted_by [User, nil]
    # @return [Boolean]
    def destroy(deleted_in: SecureRandom.uuid, deleted_by: nil)
      update(deleted: true, deleted_in:, deleted_by:)
    end

    # Soft-deletes a record.
    #
    # @param deleted_in [String]
    # @param deleted_by [User, nil]
    # @return [Boolean]
    def destroy!(deleted_in: SecureRandom.uuid, deleted_by: nil)
      update!(deleted: true, deleted_in:, deleted_by:)
    end

    # Soft-deletes a record without running validations or callbacks.
    #
    # @param deleted_in [String]
    # @param deleted_by [User]
    # @return [Boolean]
    def delete(deleted_in: SecureRandom.uuid, deleted_by: nil)
      update_columns(deleted_at: Time.current, updated_at: Time.current, deleted_in:, deleted_by_id: deleted_by&.id) # rubocop:disable Rails/SkipsModelValidations
    end

    # Restores a soft-deleted record.
    #
    # @return [Boolean]
    def restore
      update(deleted: false)
    end

    # Restores a soft-deleted record.
    #
    # @return [Boolean]
    def restore!
      update!(deleted: false)
    end

    # Restores a soft-deleted record without running validations or callbacks.
    #
    # @return [Boolean]
    def undelete
      update_columns(deleted_at: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

  private

    # @return [void]
    def run_soft_delete_callbacks(&)
      run_callbacks(:soft_delete, &)
    end

    # @return [void]
    def run_restore_callbacks(&)
      run_callbacks(:restore, &)
    end

    # @return [void]
    def run_soft_delete_commit_callbacks
      run_callbacks(:soft_delete_commit)
    end

    # @return [void]
    def run_restore_commit_callbacks
      run_callbacks(:restore_commit)
    end
  end
end
