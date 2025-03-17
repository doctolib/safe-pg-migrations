# frozen_string_literal: true

module SafePgMigrations
  module StatementRetrier
    include Helpers::StatementsHelper
    include Helpers::PgHelper

    RETRIABLE_SCHEMA_STATEMENTS.each do |method|
      define_method method do |*args, **options, &block|
        retry_if_lock_timeout { super(*args, **options, &block) }
      end
    end

    private

    def retry_if_lock_timeout
      @lock_timeout = SafePgMigrations.config.lock_timeout
      number_of_retries = 0
      begin
        number_of_retries += 1
        yield
      rescue ActiveRecord::LockWaitTimeout => e
        # Retrying is useless if we're inside a transaction.
        raise e if transaction_open? || number_of_retries >= SafePgMigrations.config.max_tries

        retry_delay = SafePgMigrations.config.retry_delay
        Helpers::Logger.say "Retrying in #{retry_delay} seconds...", sub_item: true

        if SafePgMigrations.config.increase_lock_timeout_on_retry && !SafePgMigrations.config.lock_timeout.nil?
          increase_lock_timeout
        end

        sleep retry_delay
        Helpers::Logger.say 'Retrying now.', sub_item: true
        retry
      end
    end

    def increase_lock_timeout
      Helpers::Logger.say "  Increasing the lock timeout... Currently set to #{pg_duration(@lock_timeout)}",
                          sub_item: true
      @lock_timeout += lock_timeout_step
      unless @lock_timeout < SafePgMigrations.config.max_lock_timeout_for_retry
        @lock_timeout = SafePgMigrations.config.max_lock_timeout_for_retry
      end
      execute("SET lock_timeout TO '#{pg_duration(@lock_timeout)}'")
      Helpers::Logger.say "  Lock timeout is now set to #{pg_duration(@lock_timeout)}", sub_item: true
    end

    def lock_timeout_step
      return @lock_timeout_step if defined?(@lock_timeout_step)

      max_lock_timeout_for_retry = SafePgMigrations.config.max_lock_timeout_for_retry
      lock_timeout = SafePgMigrations.config.lock_timeout
      max_tries = SafePgMigrations.config.max_tries
      @lock_timeout_step = (max_lock_timeout_for_retry - lock_timeout) / (max_tries - 1)
    end
  end
end
