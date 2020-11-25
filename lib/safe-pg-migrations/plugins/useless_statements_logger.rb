# frozen_string_literal: true

module SafePgMigrations
  module UselessStatementsLogger
    def self.disable_ddl_transaction
      SafePgMigrations.say '/!\\ No need to explicitly disable DDL transaction, safe-pg-migrations does it for you'
    end

    def add_index(table_name, column_name, **options)
      if options[:algorithm] == :concurrently
        SafePgMigrations.say(
          '/!\\ No need to explicitly use `algorithm: :concurrently`, safe-pg-migrations does it for you',
          true
        )
      end
      super
    end
  end
end
