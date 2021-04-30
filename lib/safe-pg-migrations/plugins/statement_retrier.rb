# frozen_string_literal: true

module SafePgMigrations
  module StatementRetrier
    RETRIABLE_SCHEMA_STATEMENTS = %i[
      add_column add_foreign_key remove_foreign_key change_column_default change_column_null remove_column
    ].freeze

    RETRIABLE_SCHEMA_STATEMENTS.each do |method|
      define_method method do |*args, &block|
        retry_if_lock_timeout { super(*args, &block) }
      end
      ruby2_keywords method if respond_to?(:ruby2_keywords, true)
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

        retry_delay = SafePgMigrations.config.retry_delay
        SafePgMigrations.say "Retrying in #{retry_delay} seconds...", true
        sleep retry_delay
        SafePgMigrations.say 'Retrying now.', true
        retry
      end
    end
  end
end
