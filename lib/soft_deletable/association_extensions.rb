# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    class << self
      #: (singleton(ActiveRecord::Base) model, Symbol association_name) -> void
      def install_dependency_callbacks(model, association_name)
        model.before_soft_delete(-> (o) { o.association(association_name).handle_soft_delete_dependency })
        model.after_restore(-> (o) { o.association(association_name).handle_restore_dependency })
      end

      #: (singleton(ActiveRecord::Base) model) -> void
      def install_dependency_callbacks_for_declared_associations(model)
        model.reflect_on_all_associations.each do |reflection|
          next if reflection.options[:dependent].blank?
          next unless reflection.association_class.method_defined?(:handle_soft_delete_dependency)

          install_dependency_callbacks(model, reflection.name)
        end
      end
    end

    module HasManyExtension
      DEFAULT_DESTROY_ASSOCIATION_ASYNC_BATCH_SIZE = 1000
      SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE = %i[destroy destroy_async delete_all].freeze

      # Called when an owner of a has_many association is soft deleted.
      #
      #: -> void
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
      #: -> void
      def handle_restore_dependency
        return unless should_cascade_restore?

        # records that were deleted in the same transaction as the owner
        scope = self.scope.unscope(:order).unscope_deleted.deleted.where(deleted_in: owner.deleted_in)
        send(:"cascade_restore_for_dependent_#{options[:dependent]}", scope)
      end

    private

      #: -> bool
      def should_cascade_soft_delete?
        klass.try(:soft_deletable?) &&
          options[:dependent].in?(SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE)
      end

      #: (**untyped attributes) -> void
      def cascade_soft_delete_for_dependent_destroy(**attributes)
        load_target.each { |record| record.destroy!(**attributes) }
        reset # purge the association cache
      end

      #: (**untyped attributes) -> void
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

      #: (deleted_by: ActiveRecord::Base?, deleted_in: String) -> void
      def cascade_soft_delete_for_dependent_delete_all(deleted_by:, deleted_in:)
        scope.unscope(:order).update_all( # rubocop:disable Rails/SkipsModelValidations
          deleted_at: owner.deleted_at || Time.current,
          deleted_by_id: deleted_by&.id,
          deleted_in:,
          updated_at: Time.current
        )
        reset # purge the association cache
      end

      #: (**untyped attributes) -> void
      def cascade_soft_delete_for_unpersisted_records(**attributes)
        target.each { |record| record.mark_for_destruction(**attributes) }
      end

      #: -> bool
      def should_cascade_restore?
        should_cascade_soft_delete? && owner.deleted_in.present?
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
        scope.update_all(deleted_at: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        reset # purge the association cache
      end
    end

    module HasOneExtension
      SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE = %i[destroy destroy_async delete].freeze

      # Called when an owner of a has_one association is soft deleted.
      #
      #: -> void
      def handle_soft_delete_dependency
        return unless should_cascade_soft_delete?

        record = load_target
        return unless record # Nothing to do if there's no associated record to delete

        attributes = { deleted_by: owner.deleted_by, deleted_in: owner.deleted_in }

        if owner.persisted?
          send(:"cascade_soft_delete_for_dependent_#{options[:dependent]}", record, **attributes)
        else
          # handle the case where a record is created in a deleted state
          cascade_soft_delete_for_unpersisted_records(record, **attributes)
        end
      end

      # Called when an owner of a has_one association is restored.
      #
      #: -> void
      def handle_restore_dependency
        return unless should_cascade_restore?

        record = scope.unscope_deleted.deleted.where(deleted_in: owner.deleted_in).first
        return unless record # Nothing to do if there's no associated record to restore

        send(:"cascade_restore_for_dependent_#{options[:dependent]}", record)

        reset # purge the association cache
      end

    private

      #: -> bool
      def should_cascade_soft_delete?
        klass.try(:soft_deletable?) &&
          options[:dependent].in?(SUPPORTED_DEPENDENTS_FOR_SOFT_DELETE)
      end

      #: (ActiveRecord::Base record, **untyped attributes) -> void
      def cascade_soft_delete_for_dependent_destroy(record, **attributes)
        record.destroy!(**attributes)
      end

      #: (ActiveRecord::Base record, **untyped attributes) -> void
      def cascade_soft_delete_for_dependent_destroy_async(record, **attributes)
        owner.class.soft_delete_async_job.perform_later(klass.name, [record.id], **attributes)
      end

      #: (ActiveRecord::Base record, **untyped attributes) -> void
      def cascade_soft_delete_for_dependent_delete(record, **attributes)
        record.delete(**attributes)
      end

      #: (ActiveRecord::Base record, **untyped attributes) -> void
      def cascade_soft_delete_for_unpersisted_records(record, **attributes)
        record.mark_for_destruction(**attributes)
      end

      #: -> bool
      def should_cascade_restore?
        should_cascade_soft_delete? && owner.deleted_in.present?
      end

      #: (ActiveRecord::Base record) -> void
      def cascade_restore_for_dependent_destroy(record)
        record.restore!
      end

      #: (ActiveRecord::Base record) -> void
      def cascade_restore_for_dependent_destroy_async(record)
        owner.class.restore_async_job.perform_later(klass.name, [record.id])
      end

      #: (ActiveRecord::Base record) -> void
      def cascade_restore_for_dependent_delete(record)
        record.undelete
      end
    end

    module AssociationBuilderExtension
      module ClassMethods
        #: (
        #|   singleton(ActiveRecord::Base) model,
        #|   ActiveRecord::Reflection::AssociationReflection reflection
        #| ) -> void
        def add_destroy_callbacks(model, reflection)
          result = super

          model.try(:soft_deletable?) and
            AssociationExtensions.install_dependency_callbacks(model, reflection.name)

          result
        end
      end

      #: (singleton(ActiveRecord::Associations::Association) base) -> void
      def self.prepended(base)
        super
        class << base
          prepend(ClassMethods)
        end
      end
    end
  end
end
