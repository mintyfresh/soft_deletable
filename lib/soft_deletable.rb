# frozen_string_literal: true

require 'soft_deletable/config'
require 'soft_deletable/version'
require 'soft_deletable/engine'

module SoftDeletable
  autoload :AssociationExtensions, 'soft_deletable/association_extensions'
  autoload :MigrationExtensions, 'soft_deletable/migration_extensions'
  autoload :TableExtensions, 'soft_deletable/table_extensions'

  def self.included(base)
    super
    ActiveSupport::Deprecation.warn(
      'Including SoftDeletable directly is deprecated. ' \
      'Please include the SoftDeletable::Model module instead.'
    )
    base.include(SoftDeletable::Model)
  end

  # @return [SoftDeletable::Config]
  def self.config
    @config ||= Config.new.freeze
  end

  # @yieldparam config [SoftDeletable::Config]
  # @return [void]
  def self.configure
    config = self.config.dup
    yield(config)
    @config = config.freeze
  end

  # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
  # @return [Symbol]
  def self.supports_bigint_columns?(connection)
    connection.native_database_types.key?(:bigint)
  end

  # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
  # @return [Boolean]
  def self.supports_uuid_columns?(connection)
    connection.native_database_types.key?(:uuid)
  end

  # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
  # @return [Symbol]
  def self.default_primary_key_type(connection)
    Rails.configuration.generators.options.dig(:active_record, :primary_key_type) || (
      supports_bigint_columns?(connection) ? :bigint : :integer
    )
  end
end
