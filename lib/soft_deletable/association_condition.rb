# typed: true
# frozen_string_literal: true

module SoftDeletable
  # Filters associated records by their deleted state, according to the `includes_deleted` option of an association:
  # * `:never` - Only non-deleted records are associated
  # * `:together` - Non-deleted owners are associated with non-deleted records,
  #   and deleted owners are associated with records that were deleted in the same operation (ie. the same `deleted_in`)
  # * `:always` - Records are associated regardless of their deleted state
  module AssociationCondition
    MODES = %i[never together always].freeze

    class << self
      # Resolves the `includes_deleted` mode of an association.
      # Defaults to `:always` for belongs_to, and `:together` otherwise.
      #
      #: (ActiveRecord::Reflection::AbstractReflection reflection) -> Symbol
      def mode(reflection)
        reflection = reflection.parent_reflection if habtm?(reflection)
        mode = reflection.options.fetch(:includes_deleted) { reflection.belongs_to? ? :always : :together }
        return mode if MODES.include?(mode)

        raise ArgumentError,
              "Unknown includes_deleted option #{mode.inspect} (must be #{MODES.map(&:inspect).join(', ')})"
      end

      # Checks if an association should be filtered by deleted state.
      # The associated model must be soft-deletable, but the owner needn't be:
      # owners that aren't soft-deletable are never deleted, so `:together` filters them like `:never`.
      #
      #: (
      #|   ActiveRecord::Reflection::AbstractReflection? reflection,
      #|   Class? klass
      #| ) -> bool
      def applies?(reflection, klass)
        return false if reflection.nil? || (reflection.through_reflection? && !habtm?(reflection))
        return false unless klass.try(:soft_deletable?)

        mode(reflection) != :always
      end

      # Checks if an association was declared by `has_and_belongs_to_many`,
      # which Rails implements as a has_many through an anonymous join model.
      # Since the join model has no deleted state, its target is filtered by the owner directly.
      #
      #: (ActiveRecord::Reflection::AbstractReflection reflection) -> bool
      def habtm?(reflection)
        reflection.try(:parent_reflection).is_a?(ActiveRecord::Reflection::HasAndBelongsToManyReflection)
      end

      # Resolves the association that defines a step between two tables of an association's chain.
      # A through reflection stands in for the association that it ultimately goes through (its source).
      # Returns nil for steps that aren't defined by an association (ie. polymorphic `source_type` steps).
      #
      #: (ActiveRecord::Reflection::AbstractReflection reflection) -> ActiveRecord::Reflection::AssociationReflection?
      def step_reflection(reflection)
        reflection = reflection.source_reflection while reflection.through_reflection?
        reflection if reflection.is_a?(ActiveRecord::Reflection::AssociationReflection)
      end

      # Builds the condition for a table joined directly to a single owner,
      # as by the last step of a through association.
      #
      #: (
      #|   ActiveRecord::Reflection::AbstractReflection reflection,
      #|   Arel::Table table,
      #|   deleted: bool,
      #|   deleted_in: String?
      #| ) -> Arel::Nodes::Node
      def owner_condition(reflection, table, deleted:, deleted_in:)
        non_deleted = table[:deleted_at].eq(nil)
        return non_deleted unless deleted && together?(reflection)

        deleted = table[:deleted_at].not_eq(nil).and(table[:deleted_in].eq(Arel::Nodes.build_quoted(deleted_in)))
        reflection.belongs_to? ? non_deleted.or(deleted) : deleted
      end

      # Filters the scope of an association loaded through a single owner.
      #
      # A deleted owner's belongs_to also includes non-deleted records, since the record it belongs to may outlive it.
      #
      #: (
      #|   ActiveRecord::Reflection::AbstractReflection reflection,
      #|   ActiveRecord::Relation scope,
      #|   deleted: bool,
      #|   deleted_in: String?
      #| ) -> ActiveRecord::Relation
      def for_owner(reflection, scope, deleted:, deleted_in:)
        return scope.where(deleted_at: nil) unless deleted && together?(reflection)

        deleted_scope = scope.where.not(deleted_at: nil).where(deleted_in:)
        reflection.belongs_to? ? scope.where(deleted_at: nil).or(deleted_scope) : deleted_scope
      end

      # Builds the condition for a table joined from another table.
      # Picks the condition based on the deleted state of each row in the joined-from table.
      #
      #: (
      #|   ActiveRecord::Reflection::AbstractReflection reflection,
      #|   Arel::Table table,
      #|   Arel::Table foreign_table,
      #|   Class? foreign_klass
      #| ) -> Arel::Nodes::Node
      def join_condition(reflection, table, foreign_table, foreign_klass)
        non_deleted = table[:deleted_at].eq(nil)
        return non_deleted unless together?(reflection) && foreign_klass.try(:soft_deletable?)

        deleted = table[:deleted_at].not_eq(nil).and(table[:deleted_in].eq(foreign_table[:deleted_in]))
        deleted = non_deleted.or(deleted) if reflection.belongs_to?

        Arel::Nodes::Case.new.when(foreign_table[:deleted_at].eq(nil)).then(non_deleted).else(deleted)
      end

      # Filters the scope of an association joined from another table.
      #
      #: (
      #|   ActiveRecord::Reflection::AbstractReflection reflection,
      #|   ActiveRecord::Relation scope,
      #|   Arel::Table table,
      #|   Arel::Table foreign_table,
      #|   Class? foreign_klass
      #| ) -> ActiveRecord::Relation
      def for_join(reflection, scope, table, foreign_table, foreign_klass)
        scope.where!(join_condition(reflection, table, foreign_table, foreign_klass))
      end

      # Filters the scope of an association preloaded for many owners.
      # Loads the union of records for all owners, to be divided between them using `matches?`.
      #
      #: (
      #|   ActiveRecord::Reflection::AbstractReflection reflection,
      #|   ActiveRecord::Relation scope,
      #|   Array[ActiveRecord::Base] owners
      #| ) -> ActiveRecord::Relation
      def for_preload(reflection, scope, owners)
        return scope.where(deleted_at: nil) unless together?(reflection)

        deleted, non_deleted = owners.partition { |owner| owner.try(:deleted?) }
        conditions = []
        conditions << scope.where(deleted_at: nil) if non_deleted.any? || (deleted.any? && reflection.belongs_to?)
        conditions << deleted_together_with(scope, deleted) if deleted.any?

        conditions.reduce(:or) || scope
      end

      # Checks if a record belongs in an owner's association, based on their deleted states.
      #
      #: (
      #|   ActiveRecord::Reflection::AbstractReflection reflection,
      #|   ActiveRecord::Base owner,
      #|   ActiveRecord::Base record
      #| ) -> bool
      def matches?(reflection, owner, record)
        return !record.deleted? unless owner.try(:deleted?) && together?(reflection)
        return true if reflection.belongs_to? && !record.deleted?

        record.deleted? && owner.deleted_in.present? && record.deleted_in == owner.deleted_in
      end

    private

      #: (ActiveRecord::Reflection::AbstractReflection reflection) -> bool
      def together?(reflection)
        mode(reflection) == :together
      end

      #: (ActiveRecord::Relation scope, Array[ActiveRecord::Base] owners) -> ActiveRecord::Relation
      def deleted_together_with(scope, owners)
        scope.where.not(deleted_at: nil).where(deleted_in: owners.filter_map(&:deleted_in).uniq)
      end
    end
  end
end
