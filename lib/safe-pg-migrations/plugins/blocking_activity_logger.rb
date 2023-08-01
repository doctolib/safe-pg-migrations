# frozen_string_literal: true

require_relative '../helpers/blocking_activity_formatter'
require_relative '../helpers/blocking_activity_selector'

module SafePgMigrations
  module BlockingActivityLogger
    include Helpers::BlockingActivityFormatter
    include Helpers::BlockingActivitySelector

    %i[
      add_check_constraint
      add_column
      add_foreign_key
      change_column_default
      change_column_null
      create_table
      remove_column
      remove_foreign_key
      drop_table
    ].each do |method|
      define_method method do |*args, &block|
        log_context = lambda do
          break unless SafePgMigrations.config.sensitive_logger

          options = args.last.is_a?(Hash) ? args.last : {}

          Helpers::Logger.say "Executing #{SafePgMigrations.current_migration.name}",
                              sensitive: true, warn_sensitive_logs: false
          Helpers::Logger.say_method_call method, *args, **options, sensitive: true, warn_sensitive_logs: false
        end

        log_blocking_queries_after_lock(log_context) do
          super(*args, &block)
        end
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

    def log_blocking_queries_after_lock(log_context)
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
      Helpers::Logger.say 'Lock timeout.', sub_item: true
      log_context.call
      queries =
        begin
          blocking_queries_retriever_thread.value
        rescue StandardError => e
          Helpers::Logger.say(
            "Error while retrieving blocking queries: #{e}",
            sub_item: true
          )
          nil
        end

      log_queries queries unless queries.nil?

      raise
    end

    def delay_before_logging
      timeout - SafePgMigrations.config.blocking_activity_logger_margin
    end

    def delay_before_retry
      SafePgMigrations.config.blocking_activity_logger_margin + SafePgMigrations.config.retry_delay
    end

    def timeout
      SafePgMigrations.config.lock_timeout || SafePgMigrations.config.safe_timeout
    end
  end
end
