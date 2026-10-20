# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    # Filters the targets of a has_and_belongs_to_many association preloaded for many owners.
    # (The join model has no deleted state, so its targets are divided between the owners by their deleted states.)
    module ThroughPreloaderExtension
      #: -> Hash[ActiveRecord::Base, Array[ActiveRecord::Base]]
      def records_by_owner
        return super unless filters_deleted?

        # memoized separately, since super memoizes the unfiltered records as @records_by_owner
        @filtered_records_by_owner ||= super.to_h do |owner, records| # rubocop:disable Naming/MemoizedInstanceVariableName
          [owner, records.select { |record| AssociationCondition.matches?(reflection, owner, record) }]
        end
      end
    end
  end
end
