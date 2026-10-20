# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    module PreloaderExtension
      # Mirrors ActiveRecord::Associations::Preloader::Association#load_records,
      # skipping records that don't match the deleted state of each owner.
      #
      #: (?Array[ActiveRecord::Base]? raw_records) -> void
      def load_records(raw_records = nil)
        return super unless filters_deleted?

        @records_by_owner = {}.compare_by_identity
        raw_records ||= loader_query.records_for([self])
        @preloaded_records = raw_records.select do |record|
          owners = owners_by_key[derive_key(record, association_key_name)] || []
          owners.reduce(false) { |assigned, owner| assign_preloaded_record(owner, record) || assigned }
        end
      end

      # Unscoped records haven't been filtered by deleted state, so they can't be associated.
      #
      #: (Array[ActiveRecord::Base]? unscoped_records) -> void
      def associate_records_from_unscoped(unscoped_records)
        super unless filters_deleted?
      end

    private

      #: -> ActiveRecord::Relation
      def build_scope
        scope = super
        filters_deleted? ? AssociationCondition.for_preload(reflection, scope, owners) : scope
      end

      #: (ActiveRecord::Base owner, ActiveRecord::Base record) -> bool
      def assign_preloaded_record(owner, record) # rubocop:disable Naming/PredicateMethod
        return false unless AssociationCondition.matches?(reflection, owner, record)

        entries = (@records_by_owner[owner] ||= [])
        return false unless reflection.collection? || entries.empty?

        entries << record
        true
      end

      #: -> bool
      def filters_deleted?
        AssociationCondition.applies?(reflection, klass)
      end
    end
  end
end
