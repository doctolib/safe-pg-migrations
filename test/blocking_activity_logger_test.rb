# frozen_string_literal: true

require 'test_helper'

class BlockingActivityLoggerTest < Minitest::Unit::TestCase
  def setup
    SafePgMigrations.instance_variable_set(:@config, nil)
    @connection = ActiveRecord::Base.connection
    @verbose_was = ActiveRecord::Migration.verbose
    @connection.create_table(:schema_migrations) { |t| t.string :version }
    ActiveRecord::SchemaMigration.create_table
    ActiveRecord::Migration.verbose = false
    @connection.execute("SET statement_timeout TO '70s'")
    @connection.execute("SET lock_timeout TO '70s'")

    SafePgMigrations.config.retry_delay = 1.second
    SafePgMigrations.config.safe_timeout = 0.5.second
    SafePgMigrations.config.blocking_activity_logger_margin = 0.1.seconds
  end

  def teardown
    ActiveRecord::SchemaMigration.drop_table
    @connection.execute('SET statement_timeout TO 0')
    @connection.execute("SET lock_timeout TO '30s'")
    @connection.drop_table(:users, if_exists: true)
    ActiveRecord::Migration.verbose = @verbose_was
  end

  def test_logger_filtered
    SafePgMigrations.config.blocking_activity_logger_verbose = false

    @connection.create_table(:users)
    @migration = blocking_access_exclusive_migration

    calls = record_calls(@migration, :write) { run_migration }.join
    assert_includes calls, 'lock type: relation'
    assert_includes calls, 'lock mode: AccessExclusiveLock'
    assert_includes calls, 'lock pid:'
    assert_includes calls, 'lock transactionid: null'
  end

  def test_logger_unfiltered
    @connection.create_table(:users)

    @migration = blocking_access_exclusive_migration
    calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    assert @connection.column_exists?(:users, :email, :string)
    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_column(:users, :email, :string)',
      '   -> Lock timeout.',
      '   -> Statement is being blocked by the following query:',
      '   -> ',
    ], calls[0..4]
    assert_match(/\s*-> transaction started 1 second ago:\s*BEGIN; SELECT 1 FROM users/, calls[5])
    assert_equal [
      '   -> ',
      '   -> Retrying in 1 seconds...',
      '   -> Retrying now.',
    ], calls[7..9]
  end

  def test_add_index_unfiltered
    SafePgMigrations.config.retry_delay = 0.4.second

    @connection.create_table(:users) { |t| t.string :name }
    @migration = blocking_migration_on_add_index
    calls = record_calls(@migration, :write) { run_migration }.map(&:first)

    assert_equal 2, calls.count { |line| line&.include? 'Statement is being blocked by the following queries' }
    assert_match(/\s*-> transaction started 0 seconds ago:\s*BEGIN; UPDATE users SET name = 'stan'/, calls[5])
    assert_match(/\s*-> transaction started 1 second ago:\s*BEGIN; UPDATE users SET name = 'stan'/, calls[11])
  end

  private

  def blocking_migration_on_add_index
    Class.new(ActiveRecord::Migration::Current) do
      def up
        thread_lock = Concurrent::CountDownLatch.new
        thread =
          Thread.new do
            ActiveRecord::Base.connection.execute("BEGIN; UPDATE users SET name = 'stan'")
            thread_lock.count_down
            sleep 1.1
            ActiveRecord::Base.connection.commit_db_transaction
          end

        thread_lock.wait # Wait for the above transaction to start.

        add_index :users, :name

        thread.join
      end
    end.new
  end

  def blocking_access_exclusive_migration
    Class.new(ActiveRecord::Migration::Current) do
      def up
        thread_lock = Concurrent::CountDownLatch.new
        thread =
          Thread.new do
            ActiveRecord::Base.connection.execute('BEGIN; SELECT 1 FROM users')
            thread_lock.count_down
            sleep 1.1
            ActiveRecord::Base.connection.commit_db_transaction
          end

        thread_lock.wait # Wait for the above transaction to start.

        add_column :users, :email, :string

        thread.join
      end
    end.new
  end
end
