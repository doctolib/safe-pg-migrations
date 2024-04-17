# frozen_string_literal: true

module SafePgMigrations
  module StatementRetrier
    include Helpers::StatementsHelper

    RETRIABLE_SCHEMA_STATEMENTS.each do |method|
      define_method method do |*args, **options, &block|
        retry_if_lock_timeout { super(*args, **options, &block) }
      end
    end

    private

    def retry_if_lock_timeout
      initial_lock_timeout = SafePgMigrations.config.lock_timeout
      number_of_retries = 0
      begin
        number_of_retries += 1
        yield
      rescue ActiveRecord::LockWaitTimeout
        # Retrying is useless if we're inside a transaction.
        if transaction_open? || number_of_retries >= SafePgMigrations.config.max_tries
          SafePgMigrations.config.lock_timeout = initial_lock_timeout
          raise
        end

        increase_lock_timeout unless SafePgMigrations.config.lock_timeout.nil?

        retry_delay = SafePgMigrations.config.retry_delay
        Helpers::Logger.say "Retrying in #{retry_delay} seconds...", sub_item: true
        sleep retry_delay
        Helpers::Logger.say 'Retrying now.', sub_item: true
        retry
      end
    end

    def increase_lock_timeout
      SafePgMigrations.config.lock_timeout += lock_timeout_step
      unless SafePgMigrations.config.lock_timeout < SafePgMigrations.config.max_lock_timeout_for_retry
        SafePgMigrations.config.lock_timeout = SafePgMigrations.config.max_lock_timeout_for_retry
      end
    end

    def lock_timeout_step
      (SafePgMigrations.config.max_lock_timeout_for_retry - SafePgMigrations.config.lock_timeout) / SafePgMigrations.config.max_tries
    end
  end
end
