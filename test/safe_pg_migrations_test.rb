# frozen_string_literal: true

require 'test_helper'

class SafePgMigrationsTest < MigrationTest
  def test_remove_transaction
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        class << self
          attr_accessor :did_open_transaction
        end

        def change
          up_only do
            self.class.did_open_transaction = transaction_open?
          end
          create_table :users
        end
      end.new

    run_migration migration
    assert connection.table_exists?(:users)
    assert_equal(
      false,
      migration.class.did_open_transaction,
      'Migrations are not executed inside a transaction with SafePgMigrations'
    )

    run_migration migration, :down
    refute connection.table_exists?(:users)
  end

  def test_change_table
    connection.create_table(:users)
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          change_table(:users) do |t|
            t.string :email
            t.references :user
          end
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }
    assert_calls [
      # Both columns are added.
      'ALTER TABLE "users" ADD "email" character varying',
      'ALTER TABLE "users" ADD "user_id" bigint',

      # An index is created because of the column reference.
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
    ], calls

    run_migration migration, :down
    refute connection.column_exists?(:users, :email)
    refute connection.column_exists?(:users, :user)
  end

  def test_verbose_sql_logging
    SafePgMigrations.stub(:verbose?, true) do
      migration =
        Class.new(ActiveRecord::Migration::Current) do
          def up
            execute('SELECT * from pg_stat_activity')
            execute('SELECT version()')
          end
        end.new

      stdout, _stderr = capture_io { run_migration migration }
      logs = stdout.split("\n").map(&:strip)

      assert_match('SHOW lock_timeout', logs[0])
      assert_match("SET lock_timeout TO '5s'", logs[1])
      assert_match('SELECT * from pg_stat_activity', logs[2])
      assert_match('SELECT version()', logs[3])
      assert_match("SET lock_timeout TO '70s'", logs[4])
    end
  end
end
