# frozen_string_literal: true

require 'safe-pg-migrations/configuration'
require 'safe-pg-migrations/plugins/blocking_activity_logger'
require 'safe-pg-migrations/plugins/statement_insurer'
require 'safe-pg-migrations/plugins/statement_retrier'

module SafePgMigrations
  PLUGINS = [
    BlockingActivityLogger,
    StatementRetrier,
    StatementInsurer,
  ].freeze

  class << self
    attr_reader :current_migration
    attr_accessor :enabled

    def setup_and_teardown(migration, connection)
      @alternate_connection = nil
      @current_migration = migration
      PLUGINS.each { |plugin| connection.extend(plugin) }
      connection.with_setting(:lock_timeout, SafePgMigrations.config.safe_timeout) { yield }
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

    def enabled?
      return ENV['SAFE_PG_MIGRATIONS'] == '1' if ENV['SAFE_PG_MIGRATIONS']
      return enabled unless enabled.nil?
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
      SafePgMigrations.enabled? || super
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
