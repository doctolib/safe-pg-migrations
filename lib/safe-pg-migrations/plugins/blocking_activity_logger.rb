# frozen_string_literal: true

require_relative 'helpers/blocking_activity_formatter'
require_relative 'helpers/blocking_activity_selector'

module SafePgMigrations
  module BlockingActivityLogger
    include ::SafePgMigrations::Helpers::BlockingActivitySelector
    include ::SafePgMigrations::Helpers::BlockingActivityFormatter

    %i[
      add_column remove_column add_foreign_key remove_foreign_key change_column_default change_column_null create_table
    ].each do |method|
      define_method method do |*args, &block|
        log_blocking_queries_when_locked { super(*args, &block) }
      end
    end

    def add_index(*args, **options)
      return super if options[:algorithm] != :concurrently

      log_blocking_queries { super }
    end

    def remove_index(*args, **options)
      return super if options[:algorithm] != :concurrently

      log_blocking_queries { super }
    end

    private

    def log_blocking_queries
      blocking_queries_retriever_thread =
        Thread.new do
          loop do
            sleep SafePgMigrations.config.retry_delay
            log_queries SafePgMigrations.alternate_connection.query(
              select_blocking_queries_sql % raw_connection.backend_pid
            )
          end
        end

      yield

      blocking_queries_retriever_thread.kill
    end

    def log_blocking_queries_when_locked
      blocking_queries_retriever_thread =
        Thread.new do
          sleep delay_before_logging
          SafePgMigrations.alternate_connection.query(select_blocking_queries_sql % raw_connection.backend_pid)
        end

      yield

      blocking_queries_retriever_thread.kill
    rescue ActiveRecord::LockWaitTimeout
      SafePgMigrations.say 'Lock timeout.', true
      queries =
        begin
          blocking_queries_retriever_thread.value
        rescue StandardError => e
          SafePgMigrations.say("Error while retrieving blocking queries: #{e}", true)
          nil
        end

      raise if queries.nil?

      log_queries queries
      raise
    end

    def delay_before_logging
      SafePgMigrations.config.safe_timeout - SafePgMigrations.config.blocking_activity_logger_margin
    end
  end
end
