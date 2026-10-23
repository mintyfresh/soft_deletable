# typed: true
# frozen_string_literal: true

module SoftDeletable
  module RelationExtension
    # Soft-deletes the live records of a soft-deletable relation without running callbacks,
    # or hard-deletes every record in the relation if `permanent` is set.
    # Relations of models that aren't soft-deletable are always hard-deleted.
    #
    #: (?deleted_in: String, ?deleted_by: ActiveRecord::Base?, ?permanent: bool) -> Integer
    def delete_all(deleted_in: SecureRandom.uuid, deleted_by: nil, permanent: false)
      return super() if permanent || !klass.try(:soft_deletable?)

      attributes = { deleted_at: Time.current, deleted_by_id: deleted_by&.id, deleted_in: }
      attributes[:updated_at] = Time.current if has_attribute?(:updated_at)

      # previously deleted records keep their deleted_in, so they aren't restored with this operation
      where(deleted_at: nil).update_all(attributes) # rubocop:disable Rails/SkipsModelValidations
    end

    # Soft-deletes the records of a soft-deletable relation in a single operation (ie. with a shared `deleted_in`),
    # or hard-deletes them if `permanent` is set, running callbacks and cascading to dependents for each record.
    # Relations of models that aren't soft-deletable are always hard-deleted.
    #
    #: (?deleted_in: String, ?deleted_by: ActiveRecord::Base?, ?permanent: bool) -> Array[ActiveRecord::Base]
    def destroy_all(deleted_in: SecureRandom.uuid, deleted_by: nil, permanent: false)
      return super() unless klass.try(:soft_deletable?)

      records.each { |record| record.destroy(deleted_in:, deleted_by:, permanent:) }.tap { reset }
    end
  end
end
