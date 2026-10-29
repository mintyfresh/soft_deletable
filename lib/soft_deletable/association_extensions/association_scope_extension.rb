# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    # Filters each step of a through association loaded from its owner.
    # (Associations without a through are filtered by AssociationExtension instead.)
    module AssociationScopeExtension
    private

      #: (ActiveRecord::Relation _scope, ActiveRecord::Base owner, Array[untyped] chain) -> ActiveRecord::Relation
      def add_constraints(_scope, owner, chain)
        scope = super
        return scope if chain.one?

        # the chain starts at the target table, and ends at the table joined to the owner
        chain.each_cons(2) do |reflection, next_reflection|
          step = AssociationCondition.step_reflection(unwrap(reflection))
          next unless AssociationCondition.applies?(step, reflection.klass)

          AssociationCondition.for_join(
            step, scope, reflection.aliased_table, next_reflection.aliased_table, next_reflection.klass
          )
        end

        filter_by_owner(scope, owner, chain)
      end

      #: (ActiveRecord::Relation scope, ActiveRecord::Base owner, Array[untyped] chain) -> ActiveRecord::Relation
      def filter_by_owner(scope, owner, chain)
        last = chain.last
        step = AssociationCondition.step_reflection(unwrap(last))
        return scope unless AssociationCondition.applies?(step, last.klass)

        association = chain.first.instance_variable_get(:@association)
        node = AssociationCondition.owner_condition(
          step, last.aliased_table,
          deleted: association.owner_deleted_for_filtering?, deleted_in: owner.try(:deleted_in)
        )

        scope.where!(node)
      end

      # Chain items wrap their reflections, as a ReflectionProxy or a RuntimeReflection (for the head of the chain).
      #
      #: (untyped reflection) -> ActiveRecord::Reflection::AbstractReflection
      def unwrap(reflection)
        reflection.try(:__getobj__) || reflection.instance_variable_get(:@reflection)
      end
    end
  end
end
