# frozen_string_literal: true

require 'safe-pg-migrations/configuration'
require 'safe-pg-migrations/helpers/satisfied_helper'
require 'safe-pg-migrations/helpers/index_helper'
require 'safe-pg-migrations/plugins/verbose_sql_logger'
require 'safe-pg-migrations/plugins/blocking_activity_logger'
require 'safe-pg-migrations/plugins/statement_insurer/add_column'
require 'safe-pg-migrations/plugins/statement_insurer'
require 'safe-pg-migrations/plugins/statement_retrier'
require 'safe-pg-migrations/plugins/idempotent_statements'
require 'safe-pg-migrations/plugins/useless_statements_logger'
require 'safe-pg-migrations/polyfills/index_definition_polyfill'
require 'safe-pg-migrations/polyfills/verbose_query_logs_polyfill'

module SafePgMigrations
  # Order matters: the bottom-most plugin will have precedence
  PLUGINS = [
    BlockingActivityLogger,
    IdempotentStatements,
    StatementRetrier,
    StatementInsurer,
    UselessStatementsLogger,
    Polyfills::IndexDefinitionPolyfill,
  ].freeze

  class << self
    attr_reader :current_migration, :pg_version_num

    def setup_and_teardown(migration, connection, &block)
      @pg_version_num = get_pg_version_num(connection)
      @alternate_connection = nil
      @current_migration = migration
      stdout_sql_logger = VerboseSqlLogger.new.setup if verbose?
      PLUGINS.each { |plugin| connection.extend(plugin) }

      connection.with_setting :lock_timeout, SafePgMigrations.config.pg_lock_timeout, &block
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

    def verbose?
      unless current_migration.class._safe_pg_migrations_verbose.nil?
        return current_migration.class._safe_pg_migrations_verbose
      end
      return ENV['SAFE_PG_MIGRATIONS_VERBOSE'] == '1' if ENV['SAFE_PG_MIGRATIONS_VERBOSE']
      return Rails.env.production? if defined?(Rails)

      false
    end

    def config
      @config ||= Configuration.new
    end

    def get_pg_version_num(connection)
      connection.query_value('SHOW server_version_num').to_i
    end
  end

  module Migration
    module ClassMethods
      attr_accessor :_safe_pg_migrations_verbose

      def safe_pg_migrations_verbose(verbose)
        @_safe_pg_migrations_verbose = verbose
      end
    end

    def exec_migration(connection, direction)
      SafePgMigrations.setup_and_teardown(self, connection) do
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
      add_check_constraint
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
