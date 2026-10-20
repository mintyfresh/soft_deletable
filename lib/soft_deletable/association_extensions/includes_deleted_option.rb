# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    # Registers the `includes_deleted` association option, which controls filtering by deleted state.
    # (See AssociationCondition for the available modes.)
    module IncludesDeletedOption
      #: -> Array[Symbol]
      def self.valid_options = [:includes_deleted]

      # Through associations are filtered by each of the associations they go through,
      # so the option must be specified on those associations instead.
      #
      #: (singleton(ActiveRecord::Base) model, ActiveRecord::Reflection::AssociationReflection reflection) -> void
      def self.build(model, reflection)
        return unless reflection.options.key?(:includes_deleted)

        if reflection.options[:through]
          raise ArgumentError,
                "#{model.name}##{reflection.name} cannot use includes_deleted on a through association. " \
                'Specify it on the associations it goes through instead.'
        end

        AssociationCondition.mode(reflection) # raises for unknown modes
      end
    end
  end
end
