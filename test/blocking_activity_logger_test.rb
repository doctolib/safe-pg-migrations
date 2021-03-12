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
  end

  def teardown
    ActiveRecord::SchemaMigration.drop_table
    @connection.execute('SET statement_timeout TO 0')
    @connection.execute("SET lock_timeout TO '30s'")
    @connection.drop_table(:users, if_exists: true)
    ActiveRecord::Migration.verbose = @verbose_was
  end


  def test_statement_retry
    @connection.create_table(:users) { |t| t.string :name }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          # Simulate a blocking transaction from another connection.
          thread_lock = Concurrent::CountDownLatch.new
          thread =
            Thread.new do
              ActiveRecord::Base.connection.execute("BEGIN; UPDATE users SET name = 'toto'")
              thread_lock.count_down
              sleep 1
              ActiveRecord::Base.connection.commit_db_transaction
            end

          thread_lock.wait # Wait for the above transaction to start.

          add_index :users, :name

          thread.join
        end
      end.new

    SafePgMigrations.config.retry_delay = 1.second
    SafePgMigrations.config.safe_timeout = 0.5.second
    SafePgMigrations.config.blocking_activity_logger_margin = 0.1.seconds

    calls = record_calls(@migration, :write) { run_migration }.map(&:first)

    puts calls
  end
end
