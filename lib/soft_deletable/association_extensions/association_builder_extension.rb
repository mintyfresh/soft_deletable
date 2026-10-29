# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module AssociationBuilderExtension
      module ClassMethods
        #: (
        #|   singleton(ActiveRecord::Base) model,
        #|   ActiveRecord::Reflection::AssociationReflection | ActiveRecord::Reflection::ThroughReflection reflection
        #| ) -> void
        def add_destroy_callbacks(model, reflection)
          result = super

          model.try(:soft_deletable?) and
            AssociationExtensions.install_dependency_callbacks(model, reflection.name)

          result
        end
      end

      #: (singleton(ActiveRecord::Associations::Builder::Association) base) -> void
      def self.prepended(base)
        super
        class << base
          prepend(ClassMethods)
        end
      end
    end
  end
end
