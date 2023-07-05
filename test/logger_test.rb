# frozen_string_literal: true

require 'test_helper'

class LoggerTest < Minitest::Test
  def test_say_sensitive_without_sensitive_logger
    migration = Class.new(ActiveRecord::Migration::Current).new
    SafePgMigrations.instance_variable_set :@current_migration, migration

    calls = record_calls(migration, :write) do
      SafePgMigrations::Helpers::Logger.say 'hello', sensitive: true
    end

    assert_includes calls, ['-- hello']
  end

  def test_say_not_sensitive_without_sensitive_logger
    logger = Minitest::Mock.new

    migration = Class.new(ActiveRecord::Migration::Current).new
    SafePgMigrations.instance_variable_set :@current_migration, migration
    SafePgMigrations.config.sensitive_logger = logger

    calls = record_calls(migration, :write) do
      SafePgMigrations::Helpers::Logger.say 'hello'
    end

    assert_includes calls, ['-- hello']
  end

  def test_say_sensitive_with_sensitive_logger
    logger = Minitest::Mock.new
    logger.expect :info, nil, ['hello']

    migration = Class.new(ActiveRecord::Migration::Current).new
    SafePgMigrations.instance_variable_set :@current_migration, migration
    SafePgMigrations.config.sensitive_logger = logger

    calls = record_calls(migration, :write) do
      SafePgMigrations::Helpers::Logger.say 'hello', sensitive: true
    end

    assert_includes calls, ['-- Sensitive data sent to sensitive logger']
    logger.verify
  end

  def test_does_not_warn_with_sensitive_logger
    logger = Minitest::Mock.new
    logger.expect :info, nil, ['hello']

    migration = Class.new(ActiveRecord::Migration::Current).new
    SafePgMigrations.instance_variable_set :@current_migration, migration
    SafePgMigrations.config.sensitive_logger = logger

    calls = record_calls(migration, :write) do
      SafePgMigrations::Helpers::Logger.say 'hello', sensitive: true, warn_sensitive_logs: false
    end

    refute_includes calls, ['-- Sensitive data sent to sensitive logger']
    logger.verify
  end

  def test_say_non_sensitive_with_sensitive_logger
    logger = Minitest::Mock.new
    # contrary to the previous test, we do give the method "info" in expect. If the method is called, the test will fail

    migration = Class.new(ActiveRecord::Migration::Current).new
    SafePgMigrations.instance_variable_set :@current_migration, migration
    SafePgMigrations.config.sensitive_logger = logger

    calls = record_calls(migration, :write) do
      SafePgMigrations::Helpers::Logger.say 'hello', sensitive: false
    end

    assert_includes calls, ['-- hello']
    logger.verify
  end
end
