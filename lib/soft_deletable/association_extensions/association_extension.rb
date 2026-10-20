# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module AssociationExtension
      # Checks if the owner should be treated as deleted when filtering its associated records.
      #
      #: -> bool
      def owner_deleted_for_filtering?
        # while a soft-delete cascades, the owner is deleted in memory but its live records have yet to be deleted
        !!owner.try(:deleted?) && !cascading?(:soft_delete)
      end

    private

      #: -> ActiveRecord::Relation?
      def association_scope
        scope = super
        return scope unless scope && filters_deleted?

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

      #: (Symbol operation) -> bool
      def cascading?(operation)
        !!instance_variable_get(:"@__cascading_#{operation}")
      end
    end
  end
end
