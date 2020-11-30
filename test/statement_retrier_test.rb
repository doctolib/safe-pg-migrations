# frozen_string_literal: true

class StatementRetrierTest < MigrationTest
  def test_statement_retry
    connection.create_table(:users)
    migration =
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

    calls = record_calls(migration, :write) { run_migration migration }.map(&:first)
    assert connection.column_exists?(:users, :email, :string)
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
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          connection.send(:retry_if_lock_timeout) do
            raise ActiveRecord::LockWaitTimeout, 'PG::LockNotAvailable: ERROR:  canceling statement due to lock timeout'
          end
        end
      end.new

    connection.expects(:sleep).times(4)
    calls =
      record_calls(migration, :write) do
        run_migration migration
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
end
