# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    autoload :AllowPermanentDeleteOption, 'soft_deletable/association_extensions/allow_permanent_delete_option'
    autoload :AssociationBuilderExtension, 'soft_deletable/association_extensions/association_builder_extension'
    autoload :AssociationExtension, 'soft_deletable/association_extensions/association_extension'
    autoload :AssociationScopeExtension, 'soft_deletable/association_extensions/association_scope_extension'
    autoload :BelongsToExtension, 'soft_deletable/association_extensions/belongs_to_extension'
    autoload :CollectionProxyExtension, 'soft_deletable/association_extensions/collection_proxy_extension'
    autoload :HasManyExtension, 'soft_deletable/association_extensions/has_many_extension'
    autoload :HasOneExtension, 'soft_deletable/association_extensions/has_one_extension'
    autoload :IncludesDeletedOption, 'soft_deletable/association_extensions/includes_deleted_option'
    autoload :JoinAssociationExtension, 'soft_deletable/association_extensions/join_association_extension'
    autoload :PreloaderExtension, 'soft_deletable/association_extensions/preloader_extension'
    autoload :ReflectionExtension, 'soft_deletable/association_extensions/reflection_extension'
    autoload :SkipRestrictionOnSoftDeleteOption,
             'soft_deletable/association_extensions/skip_restriction_on_soft_delete_option'
    autoload :ThroughPreloaderExtension, 'soft_deletable/association_extensions/through_preloader_extension'

    class << self
      #: (singleton(ActiveRecord::Base) model, Symbol association_name) -> void
      def install_dependency_callbacks(model, association_name)
        model.before_soft_delete(-> (o) { o.association(association_name).handle_soft_delete_dependency })
        model.after_restore(-> (o) { o.association(association_name).handle_restore_dependency })
      end

      #: (singleton(ActiveRecord::Base) model) -> void
      def install_dependency_callbacks_for_declared_associations(model)
        model.reflect_on_all_associations.each do |reflection|
          next if reflection.options[:dependent].blank?
          next unless reflection.association_class.method_defined?(:handle_soft_delete_dependency)

          install_dependency_callbacks(model, reflection.name)
        end
      end
    end
  end
end
