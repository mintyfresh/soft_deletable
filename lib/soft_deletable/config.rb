# typed: true
# frozen_string_literal: true

module SoftDeletable
  class Config
    KEYS = %i[
      delete_job_queue restore_job_queue user_class_name user_table_name logger skip_restriction_on_soft_delete
      allow_permanent_delete
    ].freeze

    #: Symbol | String
    attr_accessor :delete_job_queue

    #: Symbol | String
    attr_accessor :restore_job_queue

    #: String
    attr_accessor :user_class_name

    #: Symbol | String
    attr_writer :user_table_name

    #: Logger
    attr_accessor :logger

    #: bool
    attr_accessor :skip_restriction_on_soft_delete

    #: bool
    attr_accessor :allow_permanent_delete

    def initialize
      @delete_job_queue = :default
      @restore_job_queue = :default
      @user_class_name = 'User'
      @user_table_name = nil
      @logger = Rails.logger
      @skip_restriction_on_soft_delete = false
      @allow_permanent_delete = false
    end

    #: -> (Symbol | String)
    def user_table_name
      @user_table_name || begin
        user_class_name.constantize.table_name
      rescue NameError
        logger.warn(
          "User class #{user_class_name} not found. Using table name #{user_class_name.tableize}."
        )

        user_class_name.tableize
      end
    end
  end
end
