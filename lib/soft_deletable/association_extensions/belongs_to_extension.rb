# typed: true
# frozen_string_literal: true

module SoftDeletable
  module AssociationExtensions
    # Counter caches only count non-deleted records,
    # so records that are created, moved, or hard-deleted while deleted leave the counters unchanged.
    module BelongsToExtension
      #: -> void
      def increment_counters
        super unless owner.try(:deleted?)
      end

      #: -> void
      def decrement_counters
        super unless owner.try(:deleted_in_database?)
      end

      #: -> void
      def decrement_counters_before_last_save
        super unless owner.try(:deleted_before_last_save)
      end

      # Called after an owner of a belongs_to association is soft-deleted.
      # (A change of target in the same save is counted by ActiveRecord's own callback instead.)
      #
      #: -> void
      def handle_soft_delete_counters
        update_counters(-1) unless saved_change_to_target? # rubocop:disable Rails/SkipsModelValidations
      end

      # Called after an owner of a belongs_to association is restored.
      # (A change of target in the same save is counted by ActiveRecord's own callback instead.)
      #
      #: -> void
      def handle_restore_counters
        update_counters(1) unless saved_change_to_target? # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
