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

      # Called before an owner of a has_many association is hard-deleted.
      # Hard-deletes associated records regardless of their deleted state, since they'd otherwise be orphaned.
      #
      #: -> void
      def handle_dependency
        return super unless should_cascade_permanent_delete?

        ensure_permanent_cascade_allowed!
        send(:"cascade_permanent_delete_for_dependent_#{options[:dependent]}")
      end

      # Deletes all records in the collection, passing any deletion options (e.g. `permanent:`) on to `delete_all`.
      #
      #: (?Symbol? dependent, **untyped delete_options) -> Integer
      def delete_all(dependent = nil, **delete_options)
        return super(dependent) if delete_options.empty?

        # the same resolution as ActiveRecord, where :destroy also deletes without callbacks
        method = dependent || (options[:dependent] == :destroy ? :delete_all : options[:dependent])
        reject_delete_options!(:delete_all) if reflection.through_reflection? || method != :delete_all

        @__delete_options = delete_options
        super(dependent)
      ensure
        @__delete_options = nil
      end

      # Destroys all records in the collection in a single operation (ie. with a shared `deleted_in`),
      # passing any deletion options (e.g. `permanent:`) on to `destroy!`.
      #
      #: (**untyped destroy_options) -> Array[ActiveRecord::Base]
      def destroy_all(**destroy_options)
        reject_delete_options!(:destroy_all) if reflection.through_reflection? && destroy_options.any?
        return super() if reflection.through_reflection? || !klass.try(:soft_deletable?)

        @__destroy_options = { deleted_in: SecureRandom.uuid, **destroy_options }
        super()
      ensure
        @__destroy_options = nil
      end

    private

      # Mirrors ActiveRecord::Associations::HasManyAssociation#count_records,
      # ignoring the counter cache of a deleted owner, since it only counts non-deleted records,
      # whereas the association includes the records that were deleted together with the owner.
      #
      #: -> Integer
      def count_records
        return super unless filters_deleted? && owner_deleted_for_filtering?

        if (count = scope.count(:all)).zero?
          target.select!(&:new_record?)
          loaded!
        end

        [association_scope.limit_value, count].compact.min
      end

      # Deletion options would be silently ignored when the associated records aren't the ones being deleted.
      #
      #: (Symbol method_name) -> void
      def reject_delete_options!(method_name)
        raise ArgumentError,
              "#{owner.class.name}##{reflection.name} does not support deletion options for #{method_name}, " \
              'since it does not delete the associated records.'
      end

      #: (Array[ActiveRecord::Base] records, Symbol method) -> void
      def delete_records(records, method)
        return super unless method == :destroy && @__destroy_options

        records.each { |record| record.destroy!(**@__destroy_options) }
        update_counter(-records.length) unless reflection.inverse_updates_counter_cache?
      end

      #: (Symbol method, ActiveRecord::Relation scope) -> Integer
      def delete_count(method, scope)
        return super unless method == :delete_all && @__delete_options

        scope.delete_all(**@__delete_options)
      end

      # Through associations delete their join records, rather than the associated records.
      #
      #: -> bool
      def should_cascade_permanent_delete?
        should_cascade_soft_delete? && !reflection.through_reflection?
      end

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
        batch_size = owner.class.destroy_association_async_batch_size || DEFAULT_DESTROY_ASSOCIATION_ASYNC_BATCH_SIZE

        jobs = ids.each_slice(batch_size).map do |batch|
          owner.class.soft_delete_async_job.new(klass.name, batch, permanent: true)
        end

        ActiveJob.perform_all_later(jobs)
      end

      #: -> void
      def cascade_permanent_delete_for_dependent_delete_all
        scope_including_deleted.delete_all(permanent: true)
        reset # purge the association cache
      end

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
