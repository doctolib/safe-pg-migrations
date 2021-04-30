# frozen_string_literal: true

module SafePgMigrations
  module UselessStatementsLogger
    class << self
      def warn_useless(action, link = nil, *args)
        SafePgMigrations.say "/!\\ No need to explicitly use #{action}, safe-pg-migrations does it for you", *args
        SafePgMigrations.say "\t see #{link} for more details", *args if link
      end
      ruby2_keywords :warn_useless if respond_to?(:ruby2_keywords, true)
    end

    def add_index(*args)
      options = args.last.is_a?(Hash) ? args.last : {}
      warn_for_index(**options)
      super
    end
    ruby2_keywords :add_index if respond_to?(:ruby2_keywords, true)

    def remove_index(table_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      warn_for_index(**options) unless options.empty?
      super
    end
    ruby2_keywords :remove_index if respond_to?(:ruby2_keywords, true)

    def add_foreign_key(*args)
      options = args.last.is_a?(Hash) ? args.last : {}
      if options[:validate] == false
        UselessStatementsLogger.warn_useless '`validate: :false`', 'https://github.com/doctolib/safe-pg-migrations#safe_add_foreign_key'
      end
      super
    end
    ruby2_keywords :add_foreign_key if respond_to?(:ruby2_keywords, true)

    def warn_for_index(**options)
      return unless options[:algorithm] == :concurrently

      UselessStatementsLogger.warn_useless '`algorithm: :concurrently`', 'https://github.com/doctolib/safe-pg-migrations#safe_add_remove_index'
    end
  end
end
