# frozen_string_literal: true

module SafePgMigrations
  module StatementRetrier
    RETRIABLE_SCHEMA_STATEMENTS = %i[
      add_column remove_column add_foreign_key remove_foreign_key change_column_default
      change_column_null
    ].freeze

    RETRIABLE_SCHEMA_STATEMENTS.each do |method|
      define_method method do |*args, &block|
        retry_if_lock_timeout { super(*args, &block) }
      end
    end

    private

    def retry_if_lock_timeout
      remaining_tries = MAX_TRIES
      begin
        remaining_tries -= 1
        yield
      rescue ActiveRecord::LockWaitTimeout
        raise if transaction_open? # Retrying is useless if we're inside a transaction.
        raise unless remaining_tries > 0

        SafePgMigrations.say "Retrying in #{RETRY_DELAY} seconds...", true
        sleep RETRY_DELAY
        SafePgMigrations.say 'Retrying now.', true
        retry
      end
    end
  end
end
