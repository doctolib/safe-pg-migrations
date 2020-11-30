# frozen_string_literal: true

require 'test_helper'

class AddColumnTest < MigrationTest
  def test_add_column_before_pg_11
    connection.create_table(:users)
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column(:users, :admin, :boolean, default: false, null: false)
        end
      end.new

    SafePgMigrations.stub(:get_pg_version_num, 96_000) do
      execute_calls = nil
      write_calls =
        record_calls migration, :write do
          execute_calls = record_calls(connection, :execute) { run_migration migration }
        end
      assert_calls [
        # The column is added without any default.
        'ALTER TABLE "users" ADD "admin" boolean',

        # The default is added.
        'ALTER TABLE "users" ALTER COLUMN "admin" SET DEFAULT FALSE',

        # The not-null constraint is added.
        "SET statement_timeout TO '5s'",
        'ALTER TABLE "users" ALTER COLUMN "admin" SET NOT NULL',
        "SET statement_timeout TO '70s'",
      ], execute_calls

      assert_equal [
        '== 8128 : migrating ===========================================================',
        '-- add_column(:users, :admin, :boolean, {:default=>false, :null=>false})',
        '   -> add_column("users", :admin, :boolean, {})',
        '   -> change_column_default("users", :admin, false)',
        '   -> backfill_column_default("users", :admin)',
        '   -> change_column_null("users", :admin, false)',
      ], write_calls.map(&:first)[0...-3]
    end
  end

  def test_add_column_after_pg_11
    connection.create_table(:users)
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column(:users, :admin, :boolean, default: false, null: false)
        end
      end.new

    SafePgMigrations.stub(:get_pg_version_num, 110_000) do
      execute_calls = nil
      write_calls =
        record_calls(migration, :write) do
          execute_calls = record_calls(connection, :execute) { run_migration migration }
        end
      assert_calls [
        # The column is added with the default without any trick
        'ALTER TABLE "users" ADD "admin" boolean DEFAULT FALSE',

        # The not-null constraint is added.
        "SET statement_timeout TO '5s'",
        'ALTER TABLE "users" ALTER COLUMN "admin" SET NOT NULL',
        "SET statement_timeout TO '70s'",
      ], execute_calls

      assert_equal [
        '== 8128 : migrating ===========================================================',
        '-- add_column(:users, :admin, :boolean, {:default=>false, :null=>false})',
        '   -> add_column("users", :admin, :boolean, {:default=>false})',
        '   -> change_column_null("users", :admin, false)',
      ], write_calls.map(&:first)[0...-3]
    end
  end

  def test_backfill_column_default
    connection.create_table(:users) { |t| t.string :email }
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          backfill_column_default(:users, :email)
        end
      end.new

    connection.execute 'INSERT INTO users (id) values (GENERATE_SERIES(1, 5))'
    assert_equal 5, connection.query_value('SELECT count(*) FROM users WHERE email IS NULL')

    SafePgMigrations.config.batch_size = 2
    connection.change_column_default(:users, :email, 'michel@example.org')
    calls = record_calls(connection, :execute) { run_migration migration }
    assert_equal 5, connection.query_value("SELECT count(*) FROM users WHERE email = 'michel@example.org'")
    assert_calls [
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (1,2)',
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (3,4)',
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (5)',
    ], calls
  end
end
