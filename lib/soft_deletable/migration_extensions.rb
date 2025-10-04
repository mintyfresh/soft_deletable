# frozen_string_literal: true

module SoftDeletable
  module MigrationExtensions
    # @param table_name [String]
    # @param deleted_at_type [Symbol]
    # @param deleted_in_type [Symbol]
    # @param deleted_by_type [Symbol]
    # @param index [Hash, Boolean]
    # @param foreign_key [Hash, Boolean]
    # @return [void]
    def add_soft_deletable( # rubocop:disable Metrics/ParameterLists
      table_name,
      deleted_at_type: :timestamp,
      deleted_in_type: default_deleted_in_type,
      deleted_by_type: default_deleted_by_type,
      index: true,
      foreign_key: default_deleted_by_foreign_key_options
    )
      add_column table_name, :deleted_at, deleted_at_type
      add_column table_name, :deleted_in, deleted_in_type
      add_belongs_to table_name, :deleted_by, foreign_key:, index:, type: deleted_by_type
    end

    # @param table_name [String]
    # @param deleted_at_type [Symbol]
    # @param deleted_in_type [Symbol]
    # @param deleted_by_type [Symbol]
    # @param index [Hash, Boolean]
    # @param foreign_key [Hash, Boolean]
    # @return [void]
    def remove_soft_deletable( # rubocop:disable Metrics/ParameterLists
      table_name,
      deleted_at_type: :timestamp,
      deleted_in_type: default_deleted_in_type,
      deleted_by_type: default_deleted_by_type,
      index: true,
      foreign_key: default_deleted_by_foreign_key_options
    )
      remove_belongs_to table_name, :deleted_by, foreign_key:, index:, type: deleted_by_type
      remove_column table_name, :deleted_in, deleted_in_type
      remove_column table_name, :deleted_at, deleted_at_type
    end

  private

    # @return [Symbol]
    def default_deleted_in_type
      SoftDeletable.supports_uuid_columns?(connection) ? :uuid : :string
    end

    # @return [Symbol]
    def default_deleted_by_type
      SoftDeletable.default_primary_key_type(connection)
    end

    # @return [Hash]
    def default_deleted_by_foreign_key_options
      { to_table: SoftDeletable.config.user_table_name }
    end
  end
end
