# typed: true
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

      SoftDeletable::AssociationExtensions.install_dependency_callbacks_for_declared_associations(self)
    end

    class_methods do
      # Indicator for soft-deletable models.
      #
      #: -> bool
      def soft_deletable? = true

      # Specifies the job to use for soft-deleting records.
      # Defaults to `SoftDeletable::SoftDeleteAsyncJob`.
      #
      #: -> singleton(ActiveJob::Base)
      def soft_delete_async_job
        SoftDeletable::SoftDeleteAsyncJob
      end

      # Specifies the job to use for restoring soft-deleted records.
      # Defaults to `SoftDeletable::RestoreAsyncJob`.
      #
      #: -> singleton(ActiveJob::Base)
      def restore_async_job
        SoftDeletable::RestoreAsyncJob
      end
    end

    #: -> bool
    def deleted?
      deleted_at.present?
    end

    alias deleted deleted?

    #: (bool value) -> void
    def deleted=(value)
      if ActiveRecord::Type::Boolean.new.cast(value)
        unless deleted?
          self.deleted_at = Time.current
          self.deleted_in = SecureRandom.uuid
        end
      else
        self.deleted_at = nil
      end
    end

    #: -> bool
    def deleted_was # rubocop:disable Naming/PredicateMethod
      deleted_at_was.present?
    end

    #: -> bool
    def deleted_before_last_save # rubocop:disable Naming/PredicateMethod
      deleted_at_before_last_save.present?
    end

    #: -> bool
    def deleted_in_database # rubocop:disable Naming/PredicateMethod
      deleted_at_in_database.present?
    end

    alias deleted_in_database? deleted_in_database

    # Checks if the deleted attribute has an unsaved change.
    #
    # @param to an optional value to check against
    # @param from an optional value to check against
    #: (?to: bool, ?from: bool) -> bool
    def deleted_changed?(to: UNSPECIFIED, from: UNSPECIFIED)
      new_value = deleted
      old_value = deleted_was
      return false if new_value == old_value

      (to == UNSPECIFIED || to == new_value) &&
        (from == UNSPECIFIED || from == old_value)
    end

    # Checks if a change to the deleted attribute has been saved.
    #
    # @param to an optional value to check against
    # @param from an optional value to check against
    #: (?to: bool, ?from: bool) -> bool
    def saved_change_to_deleted?(to: UNSPECIFIED, from: UNSPECIFIED)
      new_value = deleted
      old_value = deleted_before_last_save
      return false if new_value == old_value

      (to == UNSPECIFIED || to == new_value) &&
        (from == UNSPECIFIED || from == old_value)
    end

    # Marks a record for soft-deletion when it's next saved,
    # or marks it for hard-deletion by an autosaving association if `permanent` is set.
    #
    #: (?deleted_in: String, ?deleted_by: ActiveRecord::Base?, ?permanent: bool) -> void
    def mark_for_destruction(deleted_in: SecureRandom.uuid, deleted_by: nil, permanent: false)
      # marked_for_destruction? is only set for hard-deletion, which autosave performs by calling destroy
      return super() if permanent
      return if deleted?

      self.deleted_at = Time.current
      self.deleted_in = deleted_in
      self.deleted_by = deleted_by
    end

    # Soft-deletes a record, or hard-deletes it if `permanent` is set.
    # Defaults to hard-deletion for records marked for destruction with `permanent` set.
    #
    #: (?deleted_in: String, ?deleted_by: ActiveRecord::Base?, ?permanent: bool) -> bool
    def destroy(deleted_in: SecureRandom.uuid, deleted_by: nil, permanent: marked_for_destruction?)
      return super() if permanent
      return true if deleted? && !deleted_changed?(to: true)

      update(deleted: true, deleted_in:, deleted_by:)
    end

    # Soft-deletes a record, or hard-deletes it if `permanent` is set.
    # Defaults to hard-deletion for records marked for destruction with `permanent` set.
    #
    #: (?deleted_in: String, ?deleted_by: ActiveRecord::Base?, ?permanent: bool) -> bool
    def destroy!(deleted_in: SecureRandom.uuid, deleted_by: nil, permanent: marked_for_destruction?)
      # ActiveRecord's destroy! calls destroy, which would soft-delete the record
      return destroy(permanent: true) || _raise_record_not_destroyed if permanent
      return true if deleted? && !deleted_changed?(to: true)

      update!(deleted: true, deleted_in:, deleted_by:)
    end

    # Soft-deletes a record without running validations or callbacks, or hard-deletes it if `permanent` is set.
    #
    #: (?deleted_in: String, ?deleted_by: ActiveRecord::Base?, ?permanent: bool) -> bool
    def delete(deleted_in: SecureRandom.uuid, deleted_by: nil, permanent: false)
      return super() if permanent
      return true if deleted? && !deleted_changed?(to: true)

      attributes = { deleted_at: Time.current, deleted_in:, deleted_by_id: deleted_by&.id }
      attributes[:updated_at] = Time.current if has_attribute?(:updated_at)

      update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations
    end

    # Restores a soft-deleted record.
    #
    #: -> bool
    def restore
      update(deleted: false)
    end

    # Restores a soft-deleted record.
    #
    #: -> bool
    def restore!
      update!(deleted: false)
    end

    # Restores a soft-deleted record without running validations or callbacks.
    #
    #: -> bool
    def undelete
      attributes = { deleted_at: nil }
      attributes[:updated_at] = Time.current if has_attribute?(:updated_at)

      update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations
    end

  private

    #: () { () -> void } -> void
    def run_soft_delete_callbacks(&block)
      run_callbacks(:soft_delete, &block)
    end

    #: () { () -> void } -> void
    def run_restore_callbacks(&block)
      run_callbacks(:restore, &block)
    end

    #: -> void
    def run_soft_delete_commit_callbacks
      run_callbacks(:soft_delete_commit)
    end

    #: -> void
    def run_restore_commit_callbacks
      run_callbacks(:restore_commit)
    end
  end
end
