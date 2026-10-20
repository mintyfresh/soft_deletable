# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module ReflectionExtension
      #: (Arel::Table table, Arel::Table foreign_table, singleton(ActiveRecord::Base) foreign_klass) -> ActiveRecord::Relation
      def join_scope(table, foreign_table, foreign_klass)
        scope = super
        step = AssociationCondition.step_reflection(self)
        return scope unless AssociationCondition.applies?(step, klass)

        AssociationCondition.for_join(step, scope, table, foreign_table, foreign_klass)
      end
    end
  end
end
