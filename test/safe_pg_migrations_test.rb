# frozen_string_literal: true

require 'test_helper'

class SafePgMigrationsTest < Minitest::Test
  DUMMY_MIGRATION_VERSION = 8128

  def setup
    SafePgMigrations.instance_variable_set(:@config, nil)
    SafePgMigrations.enabled = true
    @connection = ActiveRecord::Base.connection
    @verbose_was = ActiveRecord::Migration.verbose
    @connection.create_table(:schema_migrations) { |t| t.string :version }
    ActiveRecord::SchemaMigration.create_table
    ActiveRecord::Migration.verbose = false
    @connection.execute("SET statement_timeout TO '70s'")
    @connection.execute("SET lock_timeout TO '70s'")
  end

  def teardown
    ActiveRecord::SchemaMigration.drop_table
    @connection.execute('SET statement_timeout TO 0')
    @connection.execute('SET lock_timeout TO 0')
    @connection.drop_table(:users, if_exists: true)
    ActiveRecord::Migration.verbose = @verbose_was
  end

  def test_transaction_disabling
    @migration =
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

    SafePgMigrations.enabled = false
    run_migration
    assert @connection.table_exists?(:users)
    assert_equal(
      true,
      @migration.class.did_open_transaction,
      'Migrations are executed inside a transaction when SafePgMigrations is disabled'
    )

    run_migration(:down)
    refute @connection.table_exists?(:users)

    SafePgMigrations.enabled = true
    run_migration
    assert @connection.table_exists?(:users)
    assert_equal(
      false,
      @migration.class.did_open_transaction,
      'Migrations are not executed inside a transaction when SafePgMigrations is enabled'
    )
  end

  def test_statement_retry
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          # Simulate a blocking transaction from another connection.
          thread_lock = Concurrent::CountDownLatch.new
          thread =
            Thread.new do
              ActiveRecord::Base.connection.execute('BEGIN; SELECT 1 FROM users')
              thread_lock.count_down
              sleep 0.5
              ActiveRecord::Base.connection.commit_db_transaction
            end

          thread_lock.wait # Wait for the above transaction to start.

          add_column :users, :email, :string

          thread.join
        end
      end.new

    SafePgMigrations.config.retry_delay = 0.5.seconds
    SafePgMigrations.config.safe_timeout = '100ms'
    SafePgMigrations.config.blocking_activity_logger_delay = 0.05.seconds

    calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    assert @connection.column_exists?(:users, :email, :string)
    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_column(:users, :email, :string)',
      '   -> Lock timeout.',
      '   -> Statement was being blocked by the following query:',
      '   -> ',
    ], calls[0..4]
    assert_includes calls[5], '   ->   BEGIN; SELECT 1 FROM users'
    assert_equal [
      '   -> ',
      '   -> Retrying in 0.5 seconds...',
      '   -> Retrying now.',
    ], calls[6..8]
  end

  def test_retry_if_lock_timeout
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          connection.send(:retry_if_lock_timeout) do
            raise ActiveRecord::LockWaitTimeout, 'PG::LockNotAvailable: ERROR:  canceling statement due to lock timeout'
          end
        end
      end.new

    @connection.expects(:sleep).times(4)
    calls =
      record_calls(@migration, :write) do
        begin
          run_migration
          flunk 'run_migration should raise'
        rescue StandardError => e
          assert_instance_of ActiveRecord::LockWaitTimeout, e.cause
          assert_includes e.cause.message, 'canceling statement due to lock timeout'
        end
      end
    assert_equal [
      '   -> Retrying in 120 seconds...',
      '   -> Retrying now.',
      '   -> Retrying in 120 seconds...',
      '   -> Retrying now.',
    ], calls[1..4].map(&:first)
  end

  def test_add_column
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column(:users, :admin, :boolean, default: false, null: false)
        end
      end.new

    execute_calls = nil
    write_calls =
      record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end
    assert_calls [
      # The column is added without any default.
      'ALTER TABLE "users" ADD "admin" boolean',

      # The default is added.
      'ALTER TABLE "users" ALTER COLUMN "admin" SET DEFAULT FALSE',

      # The not-null constraint is added.
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ALTER "admin" SET NOT NULL',
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

  def test_change_table
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          change_table(:users) do |t|
            t.string :email
            t.references :user
          end
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      # Both columns are added.
      'ALTER TABLE "users" ADD "email" character varying',
      'ALTER TABLE "users" ADD "user_id" bigint',

      # An index is created because of the column reference.
      'SET statement_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET statement_timeout TO '70s'",
    ], calls

    run_migration(:down)
    refute @connection.column_exists?(:users, :email)
    refute @connection.column_exists?(:users, :user)
  end

  def test_create_table
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          create_table(:users) do |t|
            t.string :email
            t.references :user, foreign_key: true
          end
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      "SET statement_timeout TO '5s'",

      # Create the table with constraints.
      'CREATE TABLE "users" ("id" bigserial primary key, "email" character varying, "user_id" bigint, ' \
        'CONSTRAINT "fk_rails_6d0b8b3c2f" FOREIGN KEY ("user_id") REFERENCES "users" ("id") )',

      # Create the index.
      'SET statement_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET statement_timeout TO '5s'",

      "SET statement_timeout TO '70s'",
    ], calls

    run_migration(:down)
    refute @connection.table_exists?(:users)
  end

  def test_add_index
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_index(:users, :email)
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      'SET statement_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
      "SET statement_timeout TO '70s'",
    ], calls

    run_migration(:down)
    refute @connection.index_exists?(:users, :email)

    SafePgMigrations.enabled = false
    calls = record_calls(@connection, :execute) { run_migration }
    assert_equal 'CREATE INDEX "index_users_on_email" ON "users" ("email")', calls[3][0].squish
  end

  def test_add_index_idem_potent
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { add_index(:users, :email, name: :my_custom_index_name, where: 'email IS NOT NULL') }
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }

    assert_calls [
      'SET statement_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "my_custom_index_name" ON "users" ("email") WHERE email IS NOT NULL',
      "SET statement_timeout TO '70s'",
      "SET statement_timeout TO 0",
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_add_index_idem_potent_invalid_index
    @connection.create_table(:users) { |t| t.string :email, index: true }

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_index(:users, :email)
        end
      end.new

    @connection.stubs(:index_valid?).returns(false)
    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      'SET statement_timeout TO 0',
      'SET statement_timeout TO 0',
      'DROP INDEX CONCURRENTLY "index_users_on_email"',
      "SET statement_timeout TO '0'",
      'CREATE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
      "SET statement_timeout TO '70s'"
    ], calls
  end


  def test_add_belongs_to
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_belongs_to(:users, :user, foreign_key: true)
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      # The column is added.
      'ALTER TABLE "users" ADD "user_id" bigint',

      # The index is created concurrently.
      'SET statement_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET statement_timeout TO '70s'",

      # The foreign key is added.
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ADD CONSTRAINT "fk_rails_6d0b8b3c2f" FOREIGN KEY ("user_id") ' \
        'REFERENCES "users" ("id")',
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_backfill_column_default
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          backfill_column_default(:users, :email)
        end
      end.new

    @connection.execute 'INSERT INTO users (id) values (GENERATE_SERIES(1, 5))'
    assert_equal 5, @connection.query_value('SELECT count(*) FROM users WHERE email IS NULL')

    SafePgMigrations.config.batch_size = 2
    @connection.change_column_default(:users, :email, 'michel@example.org')
    calls = record_calls(@connection, :execute) { run_migration }
    assert_equal 5, @connection.query_value("SELECT count(*) FROM users WHERE email = 'michel@example.org'")
    assert_calls [
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (1,2)',
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (3,4)',
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (5)',
    ], calls
  end

  def test_with_setting_inside_a_failed_transaction
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        disable_ddl_transaction!
        def up
          transaction do
            with_setting(:statement_timeout, '1s') do
              execute('boom!')
            end
          end
        end
      end.new

    begin
      run_migration
      flunk 'run_migration should raise'
    rescue StandardError => e
      assert_instance_of ActiveRecord::StatementInvalid, e.cause
      assert_includes e.cause.message, 'boom!'
    end
  end

  def run_migration(direction = :up)
    @migration.version = DUMMY_MIGRATION_VERSION
    ActiveRecord::Migrator.new(direction, [@migration]).migrate
  end

  def assert_calls(expected, actual)
    assert_equal [
      "SET lock_timeout TO '5s'",
      *expected,
      "SET lock_timeout TO '70s'",
    ], actual[0...-4].map(&:first).map(&:squish)
  end

  # Records method calls on an object. Behaves like a test spy.
  #
  # Example usage:
  #
  #   record_calls(foo, :bar) { foo.bar(1, 2); foo.bar(3, 4) }
  #
  # Example return:
  #
  #   [[1, 2], [3, 4]]
  #
  def record_calls(object, method)
    calls = []
    recorder =
      lambda {
        object.stubs(method).with do |*args|
          calls << args
          # Temporarily unstub the method so that we can call the original method.
          object.unstub(method)
          begin
            # Call the original method.
            object.send(method, *args)
          ensure
            # Register the recorder again.
            recorder.call
          end
          true
        end
      }
    recorder.call
    yield
    calls
  ensure
    object.unstub(method)
  end
end
