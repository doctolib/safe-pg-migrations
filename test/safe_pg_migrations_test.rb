# frozen_string_literal: true

require 'test_helper'

class SafePgMigrationsTest < Minitest::Test
  def setup
    SafePgMigrations.instance_variable_set(:@config, nil)
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
    @connection.execute("SET lock_timeout TO '30s'")
    @connection.drop_table(:users, if_exists: true)
    ActiveRecord::Migration.verbose = @verbose_was
  end

  def test_remove_transaction
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

    run_migration
    assert @connection.table_exists?(:users)
    assert_equal(
      false,
      @migration.class.did_open_transaction,
      'Migrations are not executed inside a transaction with SafePgMigrations'
    )

    run_migration(:down)
    refute @connection.table_exists?(:users)
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
              sleep 1
              ActiveRecord::Base.connection.commit_db_transaction
            end

          thread_lock.wait # Wait for the above transaction to start.

          add_column :users, :email, :string

          thread.join
        end
      end.new

    SafePgMigrations.config.retry_delay = 1.second
    SafePgMigrations.config.safe_timeout = 0.5.second
    SafePgMigrations.config.blocking_activity_logger_margin = 0.1.seconds

    calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    assert @connection.column_exists?(:users, :email, :string)
    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_column(:users, :email, :string)',
      '   -> Lock timeout.',
      '   -> Statement was being blocked by the following query:',
      '   -> ',
    ], calls[0..4]
    assert_match(/\s*-> transaction started 1 second ago:\s*BEGIN; SELECT 1 FROM users/, calls[5])
    assert_equal [
      '   -> ',
      '   -> Retrying in 1 seconds...',
      '   -> Retrying now.',
    ], calls[7..9]
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
        run_migration
        flunk 'run_migration should raise'
      rescue StandardError => e
        assert_instance_of ActiveRecord::LockWaitTimeout, e.cause
        assert_includes e.cause.message, 'canceling statement due to lock timeout'
      end
    assert_equal [
      '   -> Retrying in 60 seconds...',
      '   -> Retrying now.',
      '   -> Retrying in 60 seconds...',
      '   -> Retrying now.',
    ], calls[1..4].map(&:first)
  end

  def test_add_column_before_pg_11
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column(:users, :admin, :boolean, default: false, null: false)
        end
      end.new

    SafePgMigrations.stub(:get_pg_version_num, 96_000) do
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
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column(:users, :admin, :boolean, default: false, null: false)
        end
      end.new

    SafePgMigrations.stub(:get_pg_version_num, 110_000) do
      execute_calls = nil
      write_calls =
        record_calls(@migration, :write) do
          execute_calls = record_calls(@connection, :execute) { run_migration }
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

  def test_create_table_idem_potent
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          create_table :users do |t|
            t.string :email
          end
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.map(&:first)

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- create_table(:users)',
      "   -> /!\\ Table 'users' already exists. Skipping statement.",
    ], write_calls[0...3]
  end

  def test_add_column_idem_potent
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { add_column :users, :name, :string }
        end
      end.new
    write_calls = record_calls(@migration, :write) { run_migration }.map(&:first)

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_column(:users, :name, :string)',
    ], write_calls[0...2]

    assert_equal [
      '-- add_column(:users, :name, :string)',
      "   -> /!\\ Column 'name' already exists in 'users'. Skipping statement.",
    ], write_calls[3..4]
  end

  def test_remove_column_idem_potent
    @connection.create_table(:users) { |t| t.string :email, index: true }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { remove_column :users, :email }
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    refute @connection.index_exists?(:users, :email)

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- remove_column(:users, :email)',
    ], write_calls[0...2]

    assert_equal [
      '-- remove_column(:users, :email)',
      "   -> /!\\ Column 'email' not found on table 'users'. Skipping statement.",
    ], write_calls[3..4]

    assert_equal write_calls.length, 8
    refute @connection.index_exists?(:users, :email)
  end

  def test_remove_index_idem_potent
    @connection.create_table(:users) { |t| t.string(:email, index: true) }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { remove_index :users, :email }
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    refute @connection.index_exists?(:users, :email)

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- remove_index(:users, :email)',
      '   -> remove_index("users", {:column=>:email, :algorithm=>:concurrently})',
    ], write_calls[0...3]

    assert_equal [
      '-- remove_index(:users, :email)',
      '   -> remove_index("users", {:column=>:email, :algorithm=>:concurrently})',
      "   -> /!\\ Index 'index_users_on_email' not found on table 'users'. Skipping statement.",
    ], write_calls[4...7]

    assert_equal write_calls.length, 10
    refute @connection.index_exists?(:users, :email)
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
      "SET lock_timeout TO '30s'",
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET lock_timeout TO '5s'",
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
      "SET lock_timeout TO '30s'",
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET lock_timeout TO '5s'",
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
      "SET lock_timeout TO '30s'",
      'CREATE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
    ], calls

    run_migration(:down)
    refute @connection.index_exists?(:users, :email)
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
      "SET lock_timeout TO '30s'",
      'CREATE INDEX CONCURRENTLY "my_custom_index_name" ON "users" ("email") WHERE email IS NOT NULL',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      "SET lock_timeout TO '30s'",
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_change_column_with_timeout
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          change_column :users, :email, :text
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }

    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ALTER COLUMN "email" TYPE text',
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
      "SET lock_timeout TO '30s'",

      'SET statement_timeout TO 0',
      "SET lock_timeout TO '30s'",
      'DROP INDEX CONCURRENTLY "index_users_on_email"',
      "SET lock_timeout TO '30s'",
      "SET statement_timeout TO '0'",

      'CREATE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
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
      "SET lock_timeout TO '30s'",
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",

      # The foreign key is added.
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ADD CONSTRAINT "fk_rails_6d0b8b3c2f" FOREIGN KEY ("user_id") ' \
        'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "users" VALIDATE CONSTRAINT "fk_rails_6d0b8b3c2f"',
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
