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
      remaining_tries = SafePgMigrations.config.max_tries
      begin
        remaining_tries -= 1
        yield
      rescue ActiveRecord::LockWaitTimeout
        raise if transaction_open? # Retrying is useless if we're inside a transaction.
        raise unless remaining_tries > 0

        number_of_retries = SafePgMigrations.config.max_tries - remaining_tries
        if SafePgMigrations.config.max_tries - remaining_tries <= 20
          SafePgMigrations.config.lock_timeout = SafePgMigrations.config.lock_timeout * number_of_retries
          SafePgMigrations.config.safe_timeout = SafePgMigrations.config.safe_timeout * number_of_retries
        else
          SafePgMigrations.config.lock_timeout = SafePgMigrations.config.lock_timeout * 20
          SafePgMigrations.config.safe_timeout = SafePgMigrations.config.safe_timeout * 20
        end

        retry_delay = SafePgMigrations.config.retry_delay
        Helpers::Logger.say "Retrying in #{retry_delay} seconds...", sub_item: true
        sleep retry_delay
        Helpers::Logger.say 'Retrying now.', sub_item: true
        retry
      end
    end
  end
end
