# frozen_string_literal: true

require 'safe-pg-migrations/configuration'
require 'safe-pg-migrations/plugins/verbose_sql_logger'
require 'safe-pg-migrations/plugins/blocking_activity_logger'
require 'safe-pg-migrations/plugins/statement_insurer'
require 'safe-pg-migrations/plugins/statement_retrier'
require 'safe-pg-migrations/plugins/idempotent_statements'
require 'safe-pg-migrations/plugins/useless_statements_logger'
require 'safe-pg-migrations/plugins/index_definition_polyfill'

module SafePgMigrations
  # Order matters: the bottom-most plugin will have precedence
  PLUGINS = [
    BlockingActivityLogger,
    IdempotentStatements,
    StatementRetrier,
    StatementInsurer,
    UselessStatementsLogger,
    IndexDefinitionPolyfill,
  ].freeze

  class << self
    attr_reader :current_migration

    def setup_and_teardown(migration, connection, force_verbose:, &block)
      @alternate_connection = nil
      @current_migration = migration
      stdout_sql_logger = VerboseSqlLogger.new.setup if verbose?(force_verbose)
      PLUGINS.each { |plugin| connection.extend(plugin) }

      connection.with_setting(:lock_timeout, SafePgMigrations.config.pg_safe_timeout, &block)
    ensure
      close_alternate_connection
      @current_migration = nil
      stdout_sql_logger&.teardown
    end

    def alternate_connection
      @alternate_connection ||= ActiveRecord::Base.connection_pool.send(:new_connection)
    end

    def close_alternate_connection
      return unless @alternate_connection

      @alternate_connection.disconnect!
      @alternate_connection = nil
    end

    ruby2_keywords def say(*args)
      return unless current_migration

      current_migration.say(*args)
    end

    ruby2_keywords def say_method_call(method, *args)
      say "#{method}(#{args.map(&:inspect) * ', '})", true
    end

    def verbose?(force_verbose)
      return force_verbose unless force_verbose.nil?
      return ENV['SAFE_PG_MIGRATIONS_VERBOSE'] == '1' if ENV['SAFE_PG_MIGRATIONS_VERBOSE']
      return Rails.env.production? if defined?(Rails)

      false
    end

    def config
      @config ||= Configuration.new
    end
  end

  module Migration
    module ClassMethods
      def safe_pg_migrations_verbose(verbose = nil)
        @_safe_pg_migrations_verbose = verbose unless verbose.nil?

        @_safe_pg_migrations_verbose
      end
    end

    def exec_migration(connection, direction)
      SafePgMigrations.setup_and_teardown(self, connection, verbose: self.class.safe_pg_migrations_verbose) do
        super(connection, direction)
      end
    end

    def disable_ddl_transaction
      UselessStatementsLogger.warn_useless '`disable_ddl_transaction`' if super
      true
    end

    SAFE_METHODS = %i[
      execute
      add_column
      add_index
      add_reference
      add_belongs_to
      change_column_null
      add_foreign_key
    ].freeze

    SAFE_METHODS.each do |method|
      define_method method do |*args|
        return super(*args) unless respond_to?(:safety_assured)

        safety_assured { super(*args) }
      end
      ruby2_keywords method
    end
  end
end
