# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module HasManyExtension
      DEFAULT_DESTROY_ASSOCIATION_ASYNC_BATCH_SIZE = 1000
      SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE = %i[destroy destroy_async delete_all].freeze

      # Called when an owner of a has_many association is soft deleted.
      #
      # @return [void]
      def handle_soft_delete_dependency
        return unless should_cascade_soft_delete?

        attributes = { deleted_by: owner.deleted_by, deleted_in: owner.deleted_in }

        if owner.persisted?
          send(:"cascade_soft_delete_for_dependent_#{options[:dependent]}", **attributes)
        else
          # handle the case where a record is created in a deleted state
          cascade_soft_delete_for_unpersisted_records(**attributes)
        end
      end

      # Called when an owner of a has_many association is restored.
      #
      # @return [void]
      def handle_restore_dependency
        return unless should_cascade_restore?

        # records that were deleted in the same transaction as the owner
        scope = self.scope.unscope(:order).unscope_deleted.deleted.where(deleted_in: owner.deleted_in)
        send(:"cascade_restore_for_dependent_#{options[:dependent]}", scope)
      end

    private

      # @return [Boolean]
      def should_cascade_soft_delete?
        klass.try(:soft_deletable?) &&
          options[:dependent].in?(SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE)
      end

      # @param attributes [Hash]
      # @return [void]
      def cascade_soft_delete_for_dependent_destroy(**attributes)
        load_target.each { |record| record.destroy!(**attributes) }
        reset # purge the association cache
      end

      # @param attributes [Hash]
      # @return [void]
      def cascade_soft_delete_for_dependent_destroy_async(**attributes)
        # mark any unpersisted records for destruction, since a job cannot process them
        target.each { |record| record.mark_for_destruction(**attributes) if record.new_record? }

        ids = scope.unscope(:order).ids
        batch_size = owner.class.destroy_association_async_batch_size || DEFAULT_DESTROY_ASSOCIATION_ASYNC_BATCH_SIZE

        jobs = ids.each_slice(batch_size).map do |batch|
          owner.class.soft_delete_async_job.new(klass.name, batch, **attributes)
        end

        ActiveJob.perform_all_later(jobs)
      end

      # @param deleted_by [ActiveRecord::Base, nil]
      # @param deleted_in [String]
      # @return [void]
      def cascade_soft_delete_for_dependent_delete_all(deleted_by:, deleted_in:)
        scope.unscope(:order).update_all( # rubocop:disable Rails/SkipsModelValidations
          deleted_at: owner.deleted_at || Time.current,
          deleted_by_id: deleted_by&.id,
          deleted_in:,
          updated_at: Time.current
        )
        reset # purge the association cache
      end

      # @param attributes [Hash]
      # @return [void]
      def cascade_soft_delete_for_unpersisted_records(**attributes)
        target.each { |record| record.mark_for_destruction(**attributes) }
      end

      # @return [Boolean]
      def should_cascade_restore?
        should_cascade_soft_delete? && owner.deleted_in.present?
      end

      # @param scope [ActiveRecord::Relation]
      # @return [void]
      def cascade_restore_for_dependent_destroy(scope)
        scope.find_each(&:restore!)
        reset # purge the association cache
      end

      # @param scope [ActiveRecord::Relation]
      # @return [void]
      def cascade_restore_for_dependent_destroy_async(scope)
        ids = scope.ids
        batch_size = owner.class.destroy_association_async_batch_size || DEFAULT_DESTROY_ASSOCIATION_ASYNC_BATCH_SIZE

        jobs = ids.each_slice(batch_size).map do |batch|
          owner.class.restore_async_job.new(klass.name, batch)
        end

        ActiveJob.perform_all_later(jobs)
      end

      # @param scope [ActiveRecord::Relation]
      # @return [void]
      def cascade_restore_for_dependent_delete_all(scope)
        scope.update_all(deleted_at: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        reset # purge the association cache
      end
    end

    module HasOneExtension
      SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE = %i[destroy destroy_async delete].freeze

      # Called when an owner of a has_one association is soft deleted.
      #
      # @return [void]
      def handle_soft_delete_dependency
        return unless should_cascade_soft_delete?

        record = load_target
        return unless record # Nothing to do if there's no associated record to delete

        attributes = { deleted_by: owner.deleted_by, deleted_in: owner.deleted_in }
        send(:"cascade_soft_delete_for_dependent_#{options[:dependent]}", record, **attributes)
      end

      # Called when an owner of a has_one association is restored.
      #
      # @return [void]
      def handle_restore_dependency
        return unless should_cascade_restore?

        record = scope.unscope_deleted.deleted.where(deleted_in: owner.deleted_in).first
        return unless record # Nothing to do if there's no associated record to restore

        send(:"cascade_restore_for_dependent_#{options[:dependent]}", record)

        reset # purge the association cache
      end

    private

      # @return [Boolean]
      def should_cascade_soft_delete?
        klass.try(:soft_deletable?) &&
          options[:dependent].in?(SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE)
      end

      # @param record [ActiveRecord::Base]
      # @param attributes [Hash]
      # @return [void]
      def cascade_soft_delete_for_dependent_destroy(record, **attributes)
        record.destroy!(**attributes)
      end

      # @param record [ActiveRecord::Base]
      # @param attributes [Hash]
      # @return [void]
      def cascade_soft_delete_for_dependent_destroy_async(record, **attributes)
        owner.class.soft_delete_async_job.perform_later(klass.name, [record.id], **attributes)
      end

      # @param record [ActiveRecord::Base]
      # @param attributes [Hash]
      # @return [void]
      def cascade_soft_delete_for_dependent_delete(record, **attributes)
        record.delete(**attributes)
      end

      # @return [Boolean]
      def should_cascade_restore?
        should_cascade_soft_delete? && owner.deleted_in.present?
      end

      # @param record [ActiveRecord::Base]
      # @return [void]
      def cascade_restore_for_dependent_destroy(record)
        record.restore!
      end

      # @param record [ActiveRecord::Base]
      # @return [void]
      def cascade_restore_for_dependent_destroy_async(record)
        owner.class.restore_async_job.perform_later(klass.name, [record.id])
      end

      # @param record [ActiveRecord::Base]
      # @return [void]
      def cascade_restore_for_dependent_delete(record)
        record.undelete
      end
    end

    module AssociationBuilderExtension
      module ClassMethods
        # @param model [Class<ActiveRecord::Base>]
        # @param reflection [ActiveRecord::Reflection::AssociationReflection]
        # @return [void]
        def add_destroy_callbacks(model, reflection)
          result = super

          if model.try(:soft_deletable?)
            name = reflection.name
            model.before_soft_delete(-> (o) { o.association(name).handle_soft_delete_dependency })
            model.after_restore(-> (o) { o.association(name).handle_restore_dependency })
          end

          result
        end
      end

      # @param base [Class<ActiveRecord::Associations::Association>]
      # @return [void]
      def self.prepended(base)
        super
        class << base
          prepend(ClassMethods)
        end
      end
    end
  end
end
