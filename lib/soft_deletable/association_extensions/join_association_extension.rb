# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    # Filters the target of a has_and_belongs_to_many association joined from its owner.
    # (The join model has no deleted state, so the target is filtered by the owner's table instead.)
    module JoinAssociationExtension
      #: (
      #|   Arel::Table foreign_table,
      #|   singleton(ActiveRecord::Base) foreign_klass,
      #|   singleton(Arel::Nodes::Join) join_type,
      #|   ActiveRecord::Associations::AliasTracker alias_tracker
      #| ) -> Array[Arel::Nodes::Join]
      def join_constraints(foreign_table, foreign_klass, join_type, alias_tracker)
        joins = super
        return joins unless AssociationCondition.habtm?(reflection) &&
                            AssociationCondition.applies?(reflection, reflection.klass)

        target_join = joins.find { |join| join.left == table }
        condition = AssociationCondition.join_condition(reflection, table, foreign_table, foreign_klass)
        append_constraints(target_join, [condition])
        joins
      end
    end
  end
end
