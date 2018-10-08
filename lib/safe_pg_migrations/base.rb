# frozen_string_literal: true

require 'safe_pg_migrations/plugins/blocking_activity_logger'
require 'safe_pg_migrations/plugins/statement_insurer'
require 'safe_pg_migrations/plugins/statement_retrier'

module SafePgMigrations
  SAFE_MODE = ENV['SAFE_PG_MIGRATIONS'] || Rails.env.production?
  SAFE_TIMEOUT = '5s'
  BLOCKING_QUERIES_LOGGER_DELAY = 4.seconds # Must be close to but smaller than SAFE_TIMEOUT.
  BATCH_SIZE = 1000
  RETRY_DELAY = 2.minutes
  MAX_TRIES = 5

  PLUGINS = [
    BlockingQueriesLogger,
    StatementRetrier,
    StatementInsurer,
  ].freeze

  class << self
    attr_reader :current_migration

    def setup_and_teardown(connection)
      @current_migration = self
      PLUGINS.each { |plugin| connection.extend(plugin) }
      connection.with_setting(:lock_timeout, SafePgMigrations::SAFE_TIMEOUT) { yield }
    ensure
      close_alternate_connection
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

    def say(*args)
      return unless current_migration

      current_migration.say(*args)
    end

    def say_method_call(method, *args)
      say "#{method}(#{args.map(&:inspect) * ', '})", true
    end
  end

  class Migration
    def exec_migration(connection, direction)
      SafePgMigrations.setup_and_teardown(connection) do
        super(connection, direction)
      end
    end

    def disable_ddl_transaction
      SafePgMigrations::SAFE_MODE || super
    end

    # Silence warnings from the strong_migrations gem.
    SAFE_METHODS = %i[execute add_column add_index add_reference add_belongs_to].freeze
    SAFE_METHODS.each do |method|
      define_method method do |*args|
        safety_assured { super(*args) }
      end
    end
  end
end
