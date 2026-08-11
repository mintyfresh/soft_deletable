# typed: true
# frozen_string_literal: true

module SoftDeletable
  module TableExtensions
    #: (
    #|   ?deleted_at_type: Symbol,
    #|   ?deleted_in_type: Symbol,
    #|   ?deleted_by_type: Symbol,
    #|   ?index: Hash[Symbol, untyped] | bool,
    #|   ?foreign_key: Hash[Symbol, untyped] | bool
    #| ) -> void
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

    #: -> Symbol
    def default_deleted_in_type
      SoftDeletable.supports_uuid_columns?(@base.delegate) ? :uuid : :string
    end

    #: -> Symbol
    def default_deleted_by_type
      SoftDeletable.default_primary_key_type(@base.delegate)
    end

    #: -> Hash[Symbol, untyped]
    def default_deleted_by_foreign_key_options
      { to_table: SoftDeletable.config.user_table_name }
    end
  end
end
