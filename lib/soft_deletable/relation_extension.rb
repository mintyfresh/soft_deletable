# typed: true
# frozen_string_literal: true

module SoftDeletable
  module RelationExtension
    # Soft-deletes the non-deleted records of a soft-deletable relation without running callbacks,
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

    # Restores the soft-deleted records of a relation without running callbacks.
    #
    #: -> Integer
    def undelete_all
      ensure_soft_deletable!(:undelete_all)

      attributes = { deleted_at: nil }
      attributes[:updated_at] = Time.current if has_attribute?(:updated_at)

      where.not(deleted_at: nil).update_all(attributes) # rubocop:disable Rails/SkipsModelValidations
    end

    # Restores the soft-deleted records of a relation,
    # running callbacks and cascading to dependents for each record.
    #
    #: -> Array[ActiveRecord::Base]
    def restore_all
      ensure_soft_deletable!(:restore_all)

      where.not(deleted_at: nil).records.each(&:restore).tap { reset }
    end

    # Restores the soft-deleted records matching the conditions (see `restore_all`).
    #
    #: (*untyped args) -> Array[ActiveRecord::Base]
    def restore_by(*args)
      ensure_soft_deletable!(:restore_by)

      where(*args).restore_all
    end

  private

    # Relations of models that aren't soft-deletable have no deleted records to restore.
    #
    #: (Symbol method_name) -> void
    def ensure_soft_deletable!(method_name)
      return if klass.try(:soft_deletable?)

      raise NoMethodError.new(
        "#{klass.name} does not support #{method_name}, since it is not soft-deletable.", method_name
      )
    end
  end
end
