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

        retry_delay = SafePgMigrations.config.retry_delay
        Helpers::Logger.say "Retrying in #{retry_delay} seconds...", sub_item: true

        increase_lock_timeout if SafePgMigrations.config.increase_lock_timeout_on_retry && !SafePgMigrations.config.lock_timeout.nil?

        sleep retry_delay
        Helpers::Logger.say 'Retrying now.', sub_item: true
        retry
      end
    end

    def increase_lock_timeout
      Helpers::Logger.say "  Increasing the lock timeout... Currently set to #{SafePgMigrations.config.lock_timeout}", sub_item: true
      SafePgMigrations.config.lock_timeout = (SafePgMigrations.config.lock_timeout + lock_timeout_step)
      unless SafePgMigrations.config.lock_timeout < SafePgMigrations.config.max_lock_timeout_for_retry
        SafePgMigrations.config.lock_timeout = SafePgMigrations.config.max_lock_timeout_for_retry
      end
      Helpers::Logger.say "  Lock timeout is now set to #{SafePgMigrations.config.lock_timeout}", sub_item: true
    end

    def lock_timeout_step
      @lock_timeout_step ||= (SafePgMigrations.config.max_lock_timeout_for_retry - SafePgMigrations.config.lock_timeout) / (SafePgMigrations.config.max_tries - 1)
    end
  end
end
