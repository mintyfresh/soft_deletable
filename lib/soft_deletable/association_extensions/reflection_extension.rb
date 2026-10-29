# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module ReflectionExtension
      #: (
      #|   Arel::Table | Arel::Nodes::TableAlias table,
      #|   Arel::Table | Arel::Nodes::TableAlias foreign_table,
      #|   singleton(ActiveRecord::Base) foreign_klass
      #| ) -> ActiveRecord::Relation
      def join_scope(table, foreign_table, foreign_klass)
        scope = super
        step = AssociationCondition.step_reflection(self)
        return scope unless AssociationCondition.applies?(step, klass)

        AssociationCondition.for_join(step, scope, table, foreign_table, foreign_klass)
      end
    end
  end
end
