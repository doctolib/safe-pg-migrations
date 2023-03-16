# frozen_string_literal: true

require_relative '../helpers/blocking_activity_formatter'
require_relative '../helpers/blocking_activity_selector'

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
        log_blocking_queries_after_lock { super(*args, &block) }
      end
      ruby2_keywords method
    end

    %i[add_index remove_index].each do |method|
      define_method method do |*args, **options, &block|
        return super(*args, **options, &block) if options[:algorithm] != :concurrently

        log_blocking_queries_loop { super(*args, **options, &block) }
      end
    end

    private

    def log_blocking_queries_loop
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

    def log_blocking_queries_after_lock
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
      SafePgMigrations.say 'Lock timeout.', true
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

    def delay_before_logging
      SafePgMigrations.config.safe_timeout -
        SafePgMigrations.config.blocking_activity_logger_margin
    end

    def delay_before_retry
      SafePgMigrations.config.blocking_activity_logger_margin + SafePgMigrations.config.retry_delay
    end
  end
end
