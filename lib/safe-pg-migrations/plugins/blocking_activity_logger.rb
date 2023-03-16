# frozen_string_literal: true

require_relative "../helpers/blocking_activity_formatter"
require_relative "../helpers/blocking_activity_selector"

module SafePgMigrations
  module BlockingActivityLogger
    include ::SafePgMigrations::Helpers::BlockingActivityFormatter
    include ::SafePgMigrations::Helpers::BlockingActivitySelector

    %i[
      add_column
      remove_column
      add_foreign_key
      remove_foreign_key
      change_column_default
      change_column_null
      create_table
    ].each do |method|
      define_method method do |*args, &block|
        log_blocking_queries { super(*args, &block) }
      end
      ruby2_keywords method
    end

    private

    def log_blocking_queries
      delay_before_logging =
        SafePgMigrations.config.safe_timeout -
          SafePgMigrations.config.blocking_activity_logger_margin

      blocking_queries_retriever_thread =
        Thread.new do
          sleep delay_before_logging
          SafePgMigrations.alternate_connection.query(
            select_blocking_queries_sql % raw_connection.backend_pid
          )
        end

      yield

      blocking_queries_retriever_thread.kill
    rescue ActiveRecord::LockWaitTimeout
      SafePgMigrations.say "Lock timeout.", true
      queries =
        begin
          blocking_queries_retriever_thread.value
        rescue StandardError => e
          SafePgMigrations.say(
            "Error while retrieving blocking queries: #{e}",
            true
          )
          nil
        end

      log_queries queries unless queries.nil?

      raise
    end
  end
end
