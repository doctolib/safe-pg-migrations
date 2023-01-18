# frozen_string_literal: true

require 'test_helper'

class VerboseSqlLoggerTest < Minitest::Test
  def setup
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          execute('SELECT * from pg_stat_activity')
          execute('SELECT version()')
        end
      end.new

    ENV.delete 'SAFE_PG_MIGRATIONS_VERBOSE'

    super
  end

  def test_logs_in_output
    SafePgMigrations.stub(:verbose?, true) do
      stdout, _stderr = capture_io { run_migration }

      assert_logs_match stdout
    end
  end

  def test_does_not_logs_in_output
    SafePgMigrations.stub(:verbose?, false) do
      stdout, stderr = capture_io { run_migration }

      assert_equal '', stdout
      assert_equal '', stderr
    end
  end

  def test_logs_with_env
    ENV['SAFE_PG_MIGRATIONS_VERBOSE'] = '1'

    stdout, = capture_io { run_migration }

    assert_logs_match stdout
  end

  def test_does_not_log_by_default
    stdout, = capture_io { run_migration }

    assert_equal '', stdout
  end

  def test_optional_sql_logging_off
    ENV['SAFE_PG_MIGRATIONS_VERBOSE'] = '1'

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        safe_pg_migrations_verbose false

        def up
          execute('SELECT * from pg_stat_activity')
          execute('SELECT version()')
        end
      end.new

    stdout, stderr = capture_io { run_migration }

    assert_equal '', stdout
    assert_equal '', stderr
  end

  def test_optional_sql_logging_on
    ENV['SAFE_PG_MIGRATIONS_VERBOSE'] = '0'
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        safe_pg_migrations_verbose true

        def up
          execute('SELECT * from pg_stat_activity')
          execute('SELECT version()')
        end
      end.new

    stdout, = capture_io { run_migration }

    assert_logs_match stdout
  end

  private

  def assert_logs_match(stdout)
    logs = stdout.split("\n").map(&:strip)

    assert_match('SHOW lock_timeout', logs[0])
    assert_match("SET lock_timeout TO '5s'", logs[1])
    assert_match('SELECT * from pg_stat_activity', logs[2])
    assert_match('SELECT version()', logs[3])
    assert_match("SET lock_timeout TO '70s'", logs[4])
  end
end
