# frozen_string_literal: true

require 'safe-pg-migrations/configuration'
require 'safe-pg-migrations/helpers/logger'
require 'safe-pg-migrations/helpers/satisfied_helper'
require 'safe-pg-migrations/helpers/index_helper'
require 'safe-pg-migrations/helpers/batch_over'
require 'safe-pg-migrations/helpers/session_setting_management'
require 'safe-pg-migrations/helpers/statements_helper'
require 'safe-pg-migrations/plugins/verbose_sql_logger'
require 'safe-pg-migrations/plugins/blocking_activity_logger'
require 'safe-pg-migrations/plugins/statement_insurer/add_column'
require 'safe-pg-migrations/plugins/statement_insurer/change_column_null'
require 'safe-pg-migrations/plugins/statement_insurer/remove_column_index'
require 'safe-pg-migrations/plugins/statement_insurer'
require 'safe-pg-migrations/plugins/statement_retrier'
require 'safe-pg-migrations/plugins/idempotent_statements'
require 'safe-pg-migrations/plugins/useless_statements_logger'
require 'safe-pg-migrations/plugins/strong_migrations_integration'
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

      with_current_migration(migration) do
        stdout_sql_logger = VerboseSqlLogger.new.setup if verbose?

        VerboseSqlLogger.new.setup if verbose?
        PLUGINS.each { |plugin| connection.extend(plugin) }

        connection.with_setting :lock_timeout, SafePgMigrations.config.pg_lock_timeout do
          connection.with_setting :statement_timeout, SafePgMigrations.config.pg_statement_timeout, &block
        end
      ensure
        stdout_sql_logger&.teardown
      end
    ensure
      close_alternate_connection
    end

    def with_current_migration(migration, &block)
      @current_migration = migration

      yield block
    ensure
      @current_migration = nil
    end

    def alternate_connection
      @alternate_connection ||= ActiveRecord::Base.connection_pool.send(:new_connection)
    end

    def close_alternate_connection
      return unless @alternate_connection

      @alternate_connection.disconnect!
      @alternate_connection = nil
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
    include StrongMigrationsIntegration

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
      SafePgMigrations.with_current_migration(self) do
        UselessStatementsLogger.warn_useless '`disable_ddl_transaction`' if super

        true
      end
    end
  end
end
