# frozen_string_literal: true

require 'safe-pg-migrations/configuration'
require 'safe-pg-migrations/plugins/verbose_sql_logger'
require 'safe-pg-migrations/plugins/blocking_activity_logger'
require 'safe-pg-migrations/plugins/statement_insurer'
require 'safe-pg-migrations/plugins/statement_retrier'
require 'safe-pg-migrations/plugins/idem_potent_statements'
require 'safe-pg-migrations/plugins/useless_statements_logger'

module SafePgMigrations
  # Order matters: the bottom-most plugin will have precedence
  PLUGINS = [
    BlockingActivityLogger,
    IdemPotentStatements,
    StatementRetrier,
    StatementInsurer,
    UselessStatementsLogger,
  ].freeze

  class << self
    attr_reader :current_migration, :pg_version_num

    def setup_and_teardown(migration, connection)
      @pg_version_num = get_pg_version_num(connection)
      @alternate_connection = nil
      @current_migration = migration
      stdout_sql_logger = VerboseSqlLogger.new.setup if verbose?
      PLUGINS.each { |plugin| connection.extend(plugin) }

      connection.with_setting(:lock_timeout, SafePgMigrations.config.pg_safe_timeout) { yield }
    ensure
      close_alternate_connection
      @current_migration = nil
      stdout_sql_logger&.teardown
    end

    def get_pg_version_num(connection)
      connection.query_value('SHOW server_version_num').to_i
    end

    def alternate_connection
      @alternate_connection ||= ActiveRecord::Base.connection_pool.send(:new_connection)
    end

    def close_alternate_connection
      return unless @alternate_connection

      @alternate_connection.disconnect!
      @alternate_connection = nil
    end

    def say(*args)
      return unless current_migration

      current_migration.say(*args)
    end

    def say_method_call(method, *args)
      say "#{method}(#{args.map(&:inspect) * ', '})", true
    end

    def verbose?
      return ENV['SAFE_PG_MIGRATIONS_VERBOSE'] == '1' if ENV['SAFE_PG_MIGRATIONS_VERBOSE']
      return Rails.env.production? if defined?(Rails)

      false
    end

    def config
      @config ||= Configuration.new
    end
  end

  module Migration
    def exec_migration(connection, direction)
      SafePgMigrations.setup_and_teardown(self, connection) do
        super(connection, direction)
      end
    end

    def disable_ddl_transaction
      UselessStatementsLogger.disable_ddl_transaction if super
      true
    end

    SAFE_METHODS = %i[execute add_column add_index add_reference add_belongs_to change_column_null].freeze
    SAFE_METHODS.each do |method|
      define_method method do |*args|
        return super(*args) unless respond_to?(:safety_assured)

        safety_assured { super(*args) }
      end
    end
  end
end
