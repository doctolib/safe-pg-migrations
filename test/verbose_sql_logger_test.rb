# frozen_string_literal: true

require 'test_helper'

class VerboseSqlLoggerTest < Minitest::Test
  def test_verbose_sql_logging
    SafePgMigrations.stub(:verbose?, true) do
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def up
            execute('SELECT * from pg_stat_activity')
            execute('SELECT version()')
          end
        end.new

      stdout, _stderr = capture_io { run_migration }
      logs = stdout.split("\n").map(&:strip)

      assert_match('SHOW lock_timeout', logs[0])
      assert_match("SET lock_timeout TO '5s'", logs[1])
      assert_match('SELECT * from pg_stat_activity', logs[2])
      assert_match('SELECT version()', logs[3])
      assert_match("SET lock_timeout TO '70s'", logs[4])
    end
  end
end
