# frozen_string_literal: true

module SafePgMigrations
  module UselessStatementsLogger
    def self.disable_ddl_transaction
      warn_useless '`disable_ddl_transaction`'
    end

    def add_index(*args, **options)
      warn_for_index(**options)
      super
    end

    def remove_index(*args, **options)
      warn_for_index(**options)
      super
    end

    def add_foreign_key(*args, validate: nil)
      if validate == false
        UselessStatementsLogger.warn_useless '`validate: :false`', 'https://github.com/doctolib/safe-pg-migrations#safe_add_foreign_key'
      end
      super
    end

    def warn_for_index(algorithm: nil)
      if algorithm == :concurrently
        UselessStatementsLogger.warn_useless '`algorithm: :concurrently`', 'https://github.com/doctolib/safe-pg-migrations#safe_add_remove_index'
      end
    end

    def self.warn_useless(action, link = nil, *args)
      SafePgMigrations.say "/!\\ No need to explicitly use #{action}, safe-pg-migrations does it for you", *args
      SafePgMigrations.say "\t see #{link} for more details", *args if link
    end
  end
end
