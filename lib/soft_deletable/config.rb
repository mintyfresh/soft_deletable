# frozen_string_literal: true

module SoftDeletable
  class Config
    KEYS = %i[delete_job_queue restore_job_queue user_class_name user_table_name logger].freeze

    # @return [Symbol, String]
    attr_accessor :delete_job_queue

    # @return [Symbol, String]
    attr_accessor :restore_job_queue

    # @return [String]
    attr_accessor :user_class_name

    # @eturn [Symbol, String]
    attr_writer :user_table_name

    # @return [Logger]
    attr_accessor :logger

    def initialize
      @delete_job_queue = :default
      @restore_job_queue = :default
      @user_class_name = 'User'
      @user_table_name = nil
      @logger = Rails.logger
    end

    # @return [Symbol, String]
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
