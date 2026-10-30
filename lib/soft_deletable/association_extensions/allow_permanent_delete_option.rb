# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    # Registers the `allow_permanent_delete` association option,
    # which allows permanently deleting an owner that isn't soft-deletable to delete its soft-deletable dependents.
    # (Defaults to `SoftDeletable.config.allow_permanent_delete`.)
    module AllowPermanentDeleteOption
      DELETING_DEPENDENTS = %i[destroy destroy_async delete delete_all].freeze

      #: -> Array[Symbol]
      def self.valid_options = [:allow_permanent_delete]

      # The option would be silently ignored by associations that don't delete their dependents.
      #
      #: (
      #|   singleton(ActiveRecord::Base) model,
      #|   ActiveRecord::Reflection::AssociationReflection | ActiveRecord::Reflection::ThroughReflection reflection
      #| ) -> void
      def self.build(model, reflection)
        return unless reflection.options.key?(:allow_permanent_delete)
        return if reflection.macro.in?(%i[has_many has_one]) && !reflection.through_reflection? &&
                  reflection.options[:dependent].in?(DELETING_DEPENDENTS)

        raise ArgumentError,
              "#{model.name}##{reflection.name} cannot use allow_permanent_delete, " \
              'since it is not a has_many or has_one association that uses ' \
              '`dependent: :destroy`, `dependent: :destroy_async`, `dependent: :delete`, or `dependent: :delete_all`.'
      end
    end
  end
end
