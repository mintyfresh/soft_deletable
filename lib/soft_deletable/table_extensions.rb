# frozen_string_literal: true

module SoftDeletable
  module TableExtensions
    # @param deleted_at_type [Symbol]
    # @param deleted_in_type [Symbol]
    # @param deleted_by_type [Symbol]
    # @param index [Hash, Boolean]
    # @param foreign_key [Hash, Boolean]
    # @return [void]
    def soft_deletable(
      deleted_at_type: :timestamp,
      deleted_in_type: default_deleted_in_type,
      deleted_by_type: default_deleted_by_type,
      index: true,
      foreign_key: default_deleted_by_foreign_key_options
    )
      column :deleted_at, deleted_at_type
      column :deleted_in, deleted_in_type
      belongs_to :deleted_by, foreign_key:, index:, type: deleted_by_type
    end

  private

    # @return [Symbol]
    def default_deleted_in_type
      SoftDeletable.supports_uuid_columns?(@conn || self) ? :uuid : :string
    end

    # @return [Symbol]
    def default_deleted_by_type
      SoftDeletable.default_primary_key_type(@conn || self)
    end

    # @return [Hash]
    def default_deleted_by_foreign_key_options
      { to_table: SoftDeletable.config.user_table_name }
    end
  end
end
