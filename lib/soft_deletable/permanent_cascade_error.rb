# typed: true
# frozen_string_literal: true

module SoftDeletable
  # Raised when an owner that isn't soft-deletable would cascade a hard-delete onto soft-deletable records.
  # Such cascades must be implemented explicitly, to avoid accidentally losing soft-deleted information.
  class PermanentCascadeError < ActiveRecord::ActiveRecordError; end
end
