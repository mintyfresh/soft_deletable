# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module AssociationExtension
      RESTRICT_DEPENDENTS = %i[restrict_with_exception restrict_with_error].freeze

      # Checks if the owner should be treated as deleted when filtering its associated records.
      #
      #: -> bool
      def owner_deleted_for_filtering?
        # until a soft-delete is saved (e.g. while validating or cascading), its associated records aren't yet deleted
        !!owner.try(:deleted_in_database?)
      end

    private

      #: -> bool
      def restricts_dependents?
        options[:dependent].in?(RESTRICT_DEPENDENTS)
      end

      # Blocks soft-deleting an owner with non-deleted associated records, as hard-deleting it would be blocked.
      #
      #: -> void
      def handle_soft_delete_restriction
        return if skip_restriction_on_soft_delete?

        # the owner is deleted in memory, but its associated records are those of a non-deleted owner
        return unless with_reentrancy_protection(:soft_delete) { soft_delete_restricted? }
        raise ActiveRecord::DeleteRestrictionError, reflection.name if options[:dependent] == :restrict_with_exception

        record = owner.class.human_attribute_name(reflection.name).downcase
        owner.errors.add(:base, :"restrict_dependent_destroy.#{reflection.macro}", record:)
        throw(:abort)
      end

      #: -> bool
      def skip_restriction_on_soft_delete?
        options.fetch(:skip_restriction_on_soft_delete) { SoftDeletable.config.skip_restriction_on_soft_delete }
      end

      # The association's scope, including associated records regardless of their deleted state.
      #
      #: -> ActiveRecord::Relation
      def scope_including_deleted
        @__including_deleted = true
        scope.unscope(:limit, :order) # has_one scopes are limited to a single record
      ensure
        @__including_deleted = false
      end

      # Hard-deleting an owner that isn't soft-deletable must not implicitly hard-delete soft-deletable records,
      # which would destroy information that soft-deletion is meant to preserve.
      #
      #: -> void
      def ensure_permanent_cascade_allowed!
        return if owner.class.try(:soft_deletable?) || allow_permanent_delete?

        raise PermanentCascadeError,
              "Cannot cascade the deletion of #{owner.class.name} to #{reflection.name}, " \
              "since #{owner.class.name} is not soft-deletable but #{klass.name} is. " \
              'Use `allow_permanent_delete: true` to permanently delete them.'
      end

      #: -> bool
      def allow_permanent_delete?
        options.fetch(:allow_permanent_delete) { SoftDeletable.config.allow_permanent_delete }
      end

      #: -> ActiveRecord::Relation?
      def association_scope
        scope = super
        return scope unless scope && filters_deleted? && !@__including_deleted

        deleted = owner_deleted_for_filtering?
        AssociationCondition.for_owner(reflection, scope, deleted:, deleted_in: owner.try(:deleted_in))
      end

      # The cached statement is shared across owners, so it can't depend on an owner's deleted state.
      # Through associations are filtered by AssociationScopeExtension, which checks the owner's deleted state.
      #
      #: (ActiveRecord::Relation scope) -> bool
      def skip_statement_cache?(scope)
        super || filters_deleted? || (reflection.through_reflection? && !!owner.class.try(:soft_deletable?))
      end

      # The deleted state of built records is managed by soft-deletion, not copied from the association scope.
      #
      #: -> Hash[String, untyped]
      def scope_for_create
        filters_deleted? ? super.except('deleted_at', 'deleted_in') : super
      end

      #: -> bool
      def filters_deleted?
        AssociationCondition.applies?(reflection, klass)
      end
    end
  end
end
