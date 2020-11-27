# frozen_string_literal: true

module SafePgMigrations
  module UselessStatementsLogger
    def self.warn_useless(action, link = nil, *args)
      SafePgMigrations.say "/!\\ No need to explicitly use #{action}, safe-pg-migrations does it for you", *args
      SafePgMigrations.say "\t see #{link} for more details", *args if link
    end

    def add_index(*, **options)
      warn_for_index(**options)
      super
    end

    def remove_index(table_name, options = {})
      warn_for_index(options) if options.is_a? Hash
      super
    end

    def add_foreign_key(*, **options)
      if options[:validate] == false
        UselessStatementsLogger.warn_useless '`validate: :false`', 'https://github.com/doctolib/safe-pg-migrations#safe_add_foreign_key'
      end
      super
    end

    def warn_for_index(**options)
      return unless options[:algorithm] == :concurrently

      UselessStatementsLogger.warn_useless '`algorithm: :concurrently`', 'https://github.com/doctolib/safe-pg-migrations#safe_add_remove_index'
    end
  end
end
