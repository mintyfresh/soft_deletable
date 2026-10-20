# frozen_string_literal: true

module SoftDeletable
  class Engine < ::Rails::Engine
    isolate_namespace SoftDeletable

    config.soft_deletable = ActiveSupport::OrderedOptions.new

    initializer 'soft_deletable.config' do
      SoftDeletable.configure do |config|
        SoftDeletable::Config::KEYS.each do |key|
          if (config_value = SoftDeletable::Engine.config.soft_deletable[key]).present?
            config.send(:"#{key}=", config_value)
          end
        end
      end
    end

    initializer 'soft_deletable.association_extensions' do
      ActiveSupport.on_load(:active_record) do
        extensions = SoftDeletable::AssociationExtensions
        ActiveRecord::Associations::HasManyAssociation.prepend(extensions::HasManyExtension)
        ActiveRecord::Associations::HasOneAssociation.prepend(extensions::HasOneExtension)
        ActiveRecord::Associations::Builder::Association.prepend(extensions::AssociationBuilderExtension)
        ActiveRecord::Associations::Builder::Association.extensions << extensions::IncludesDeletedOption
        ActiveRecord::Associations::Association.prepend(extensions::AssociationExtension)
        ActiveRecord::Associations::Preloader::Association.prepend(extensions::PreloaderExtension)
        ActiveRecord::Associations::Preloader::ThroughAssociation.prepend(extensions::ThroughPreloaderExtension)
        ActiveRecord::Associations::JoinDependency::JoinAssociation.prepend(extensions::JoinAssociationExtension)
        ActiveRecord::Reflection::AssociationReflection.prepend(extensions::ReflectionExtension)
        ActiveRecord::Reflection::ThroughReflection.prepend(extensions::ReflectionExtension)
        ActiveRecord::Associations::AssociationScope.prepend(extensions::AssociationScopeExtension)
      end
    end

    initializer 'soft_deletable.migration_extensions' do
      ActiveSupport.on_load(:active_record) do
        ActiveRecord::Migration.include SoftDeletable::MigrationExtensions
        ActiveRecord::ConnectionAdapters::TableDefinition.include SoftDeletable::TableDefinitionExtensions
        ActiveRecord::ConnectionAdapters::Table.include SoftDeletable::TableExtensions
      end
    end
  end
end
