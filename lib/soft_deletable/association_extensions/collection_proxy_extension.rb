# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    # Passes deletion options (e.g. `permanent:`) through to the association,
    # since CollectionProxy#delete_all and #destroy_all would otherwise reject them.
    module CollectionProxyExtension
      #: (**untyped destroy_options) -> Array[ActiveRecord::Base]
      def destroy_all(**destroy_options)
        @association.destroy_all(**destroy_options).tap { reset_scope }
      end

      #: (?Symbol? dependent, **untyped delete_options) -> Integer
      def delete_all(dependent = nil, **delete_options)
        return super(dependent) if delete_options.empty?

        @association.delete_all(dependent, **delete_options).tap { reset_scope }
      end
    end
  end
end
