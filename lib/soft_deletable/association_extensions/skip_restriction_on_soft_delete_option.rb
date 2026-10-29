# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    # Registers the `skip_restriction_on_soft_delete` association option,
    # which allows soft-deleting an owner despite a `dependent: :restrict_with_*` association.
    # (Defaults to `SoftDeletable.config.skip_restriction_on_soft_delete`.)
    module SkipRestrictionOnSoftDeleteOption
      #: -> Array[Symbol]
      def self.valid_options = [:skip_restriction_on_soft_delete]

      # The option would be silently ignored by associations that don't restrict deletion.
      #
      #: (
      #|   singleton(ActiveRecord::Base) model,
      #|   ActiveRecord::Reflection::AssociationReflection | ActiveRecord::Reflection::ThroughReflection reflection
      #| ) -> void
      def self.build(model, reflection)
        return unless reflection.options.key?(:skip_restriction_on_soft_delete)
        return if reflection.options[:dependent].in?(AssociationExtension::RESTRICT_DEPENDENTS)

        raise ArgumentError,
              "#{model.name}##{reflection.name} cannot use skip_restriction_on_soft_delete, " \
              'since it does not use `dependent: :restrict_with_exception` or `dependent: :restrict_with_error`.'
      end
    end
  end
end
