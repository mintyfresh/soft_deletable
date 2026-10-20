# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module HasManyExtension
      DEFAULT_DESTROY_ASSOCIATION_ASYNC_BATCH_SIZE = 1000
      SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE = %i[destroy destroy_async delete_all].freeze

      # Called before an owner of a has_many association is soft deleted.
      #
      #: -> void
      def handle_soft_delete_dependency
        return unless should_cascade_soft_delete?

        with_reentrancy_protection(:soft_delete) do
          attributes = { deleted_by: owner.deleted_by, deleted_in: owner.deleted_in }
          send(:"cascade_soft_delete_for_dependent_#{options[:dependent]}", **attributes)
        end
      end

      # Called after an owner of a has_many association is restored.
      #
      #: -> void
      def handle_restore_dependency
        return unless should_cascade_restore?

        with_reentrancy_protection(:restore) do
          # restore unpersisted records before the association cache is reset
          if (records = unpersisted_records_in_target_for_restore)
            records.each(&:restore!)
          end

          # records that were deleted in the same transaction as the owner
          scope = self.scope.unscope(:order).unscope_deleted.deleted.where(deleted_in: owner.deleted_in)
          send(:"cascade_restore_for_dependent_#{options[:dependent]}", scope)
        end
      end

    private

      #: (Symbol operation) { () -> void } -> void
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

      #: (**untyped attributes) -> void
      def cascade_soft_delete_for_dependent_destroy(**attributes)
        load_target

        unpersisted = mark_unpersisted_records_for_destruction(**attributes)
        persisted_records_in_target_for_soft_delete.each { |record| record.destroy!(**attributes) }

        self.target = unpersisted # remove deleted records from the association cache
      end

      #: (**untyped attributes) -> void
      def cascade_soft_delete_for_dependent_destroy_async(**attributes)
        if owner.persisted?
          ids = scope.unscope(:order).not_deleted.ids
        else
          ids = persisted_records_in_target_for_soft_delete.map(&:id)
        end

        # mark any unpersisted records for destruction, since a job cannot process them
        mark_unpersisted_records_for_destruction(**attributes)

        batch_size = owner.class.destroy_association_async_batch_size || DEFAULT_DESTROY_ASSOCIATION_ASYNC_BATCH_SIZE

        jobs = ids.each_slice(batch_size).map do |batch|
          owner.class.soft_delete_async_job.new(klass.name, batch, **attributes)
        end

        ActiveJob.perform_all_later(jobs)
      end

      #: (deleted_by: ActiveRecord::Base?, deleted_in: String) -> void
      def cascade_soft_delete_for_dependent_delete_all(deleted_by:, deleted_in:)
        if owner.persisted?
          scope = self.scope.unscope(:order).not_deleted
        else
          scope = klass.where(id: persisted_records_in_target_for_soft_delete.map(&:id))
        end

        # mark any unpersisted records for destruction, since update_all cannot modify them
        unpersisted = mark_unpersisted_records_for_destruction(deleted_by:, deleted_in:)

        attributes = { deleted_at: Time.current, deleted_by_id: deleted_by&.id, deleted_in: }
        attributes[:updated_at] = Time.current if scope.has_attribute?(:updated_at)
        scope.update_all(attributes) # rubocop:disable Rails/SkipsModelValidations

        self.target = unpersisted # remove deleted records from the association cache
      end

      #: -> Array[ActiveRecord::Base]
      def persisted_records_in_target_for_soft_delete
        target&.select { |record| record.persisted? && !record.deleted? } || []
      end

      #: (**untyped attributes) -> Array[ActiveRecord::Base]
      def mark_unpersisted_records_for_destruction(**attributes)
        unpersisted = target&.select(&:new_record?) || []
        unpersisted.each { |record| record.mark_for_destruction(**attributes) }
        unpersisted
      end

      #: -> bool
      def should_cascade_restore?
        should_cascade_soft_delete? && owner.deleted_in.present?
      end

      #: -> Array[ActiveRecord::Base]?
      def unpersisted_records_in_target_for_restore
        target&.select { |record| record.new_record? && record.deleted? && record.deleted_in == owner.deleted_in }
      end

      #: (ActiveRecord::Relation scope) -> void
      def cascade_restore_for_dependent_destroy(scope)
        scope.find_each(&:restore!)
        reset # purge the association cache
      end

      #: (ActiveRecord::Relation scope) -> void
      def cascade_restore_for_dependent_destroy_async(scope)
        ids = scope.ids
        batch_size = owner.class.destroy_association_async_batch_size || DEFAULT_DESTROY_ASSOCIATION_ASYNC_BATCH_SIZE

        jobs = ids.each_slice(batch_size).map do |batch|
          owner.class.restore_async_job.new(klass.name, batch)
        end

        ActiveJob.perform_all_later(jobs)
      end

      #: (ActiveRecord::Relation scope) -> void
      def cascade_restore_for_dependent_delete_all(scope)
        attributes = { deleted_at: nil }
        attributes[:updated_at] = Time.current if scope.has_attribute?(:updated_at)
        scope.update_all(attributes) # rubocop:disable Rails/SkipsModelValidations

        reset # purge the association cache
      end
    end
  end
end
