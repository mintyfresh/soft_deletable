# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module HasOneExtension
      SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE = %i[destroy destroy_async delete].freeze

      # Called before an owner of a has_one association is soft deleted.
      #
      #: -> void
      def handle_soft_delete_dependency
        return handle_soft_delete_restriction if restricts_dependents?
        return unless should_cascade_soft_delete?

        with_reentrancy_protection(:soft_delete) do
          record = load_target
          return unless record # Nothing to do if there's no associated record to delete

          attributes = { deleted_by: owner.deleted_by, deleted_in: owner.deleted_in }

          if owner.persisted? && record.persisted?
            send(:"cascade_soft_delete_for_dependent_#{options[:dependent]}", record, **attributes)
          else
            # handle the case where an owner is created in a deleted state
            record.mark_for_destruction(**attributes)
          end
        end
      end

      # Called after an owner of a has_one association is restored.
      #
      #: -> void
      def handle_restore_dependency
        return unless should_cascade_restore?

        with_reentrancy_protection(:restore) do
          unless (record = record_for_restore)
            return # no associated record to restore
          end

          if record.persisted?
            send(:"cascade_restore_for_dependent_#{options[:dependent]}", record)
          else
            record.restore!
          end

          # load the association with the restored record
          self.target = record unless record.deleted?
        end
      end

      # Called before an owner of a has_one association is hard-deleted.
      # Hard-deletes associated records regardless of their deleted state, since they'd otherwise be orphaned.
      #
      #: -> void
      def handle_dependency
        return super unless should_cascade_soft_delete?

        ensure_permanent_cascade_allowed!
        send(:"cascade_permanent_delete_for_dependent_#{options[:dependent]}")
      end

    private

      #: -> void
      def cascade_permanent_delete_for_dependent_destroy
        scope_including_deleted.find_each do |record|
          record.destroyed_by_association = reflection
          record.destroy!(permanent: true)
        end

        reset # purge the association cache
      end

      #: -> void
      def cascade_permanent_delete_for_dependent_destroy_async
        ids = scope_including_deleted.ids
        klass.soft_delete_async_job.perform_later(klass.name, ids, permanent: true) if ids.any?
      end

      #: -> void
      def cascade_permanent_delete_for_dependent_delete
        scope_including_deleted.delete_all(permanent: true)
        reset # purge the association cache
      end

      #: -> bool
      def soft_delete_restricted?
        record = load_target
        !!record && !record.try(:deleted?)
      end

      #: [T] (Symbol operation) { () -> T } -> T?
      def with_reentrancy_protection(operation, &block)
        name = :"@__cascading_#{operation}"
        return if instance_variable_get(name)

        instance_variable_set(name, true)
        yield
      ensure
        instance_variable_set(name, false)
      end

      #: -> bool
      def should_cascade_soft_delete?
        klass.try(:soft_deletable?) &&
          options[:dependent].in?(SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE)
      end

      #: (ActiveRecord::Base record, **untyped attributes) -> void
      def cascade_soft_delete_for_dependent_destroy(record, **attributes)
        record.destroy!(**attributes) unless record.deleted?
        reset # purge the association cache
      end

      #: (ActiveRecord::Base record, **untyped attributes) -> void
      def cascade_soft_delete_for_dependent_destroy_async(record, **attributes)
        owner.class.soft_delete_async_job.perform_later(klass.name, [record.id], **attributes) unless record.deleted?
      end

      #: (ActiveRecord::Base record, **untyped attributes) -> void
      def cascade_soft_delete_for_dependent_delete(record, **attributes)
        record.delete(**attributes) unless record.deleted?
        reset # purge the association cache
      end

      #: -> bool
      def should_cascade_restore?
        should_cascade_soft_delete? && owner.deleted_in.present?
      end

      #: -> ActiveRecord::Base?
      def record_for_restore
        if (target = self.target) && target.deleted? && target.deleted_in == owner.deleted_in
          target
        elsif (record = scope.unscope_deleted.deleted.find_by(deleted_in: owner.deleted_in))
          record
        end
      end

      #: (ActiveRecord::Base record) -> void
      def cascade_restore_for_dependent_destroy(record)
        record.restore! if record.deleted?
      end

      #: (ActiveRecord::Base record) -> void
      def cascade_restore_for_dependent_destroy_async(record)
        owner.class.restore_async_job.perform_later(klass.name, [record.id]) if record.deleted?
      end

      #: (ActiveRecord::Base record) -> void
      def cascade_restore_for_dependent_delete(record)
        record.undelete if record.deleted?
      end
    end
  end
end
