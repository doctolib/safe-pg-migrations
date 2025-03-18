# frozen_string_literal: true

require 'test_helper'

class StatementRetrierTest < Minitest::Test
  def test_lock_timeout_increase_on_retry
    SafePgMigrations.config.lock_timeout = 0.1.seconds
    SafePgMigrations.config.increase_lock_timeout_on_retry = true

    2.times do
      calls = calls_for_lock_timeout_migration

      assert_equal [
        '   -> Retrying in 60 seconds...',
        '   ->   Increasing the lock timeout... Currently set to 100ms',
        '   ->   Lock timeout is now set to 325ms',
        '   -> Retrying now.',
        '   -> Retrying in 60 seconds...',
        '   ->   Increasing the lock timeout... Currently set to 325ms',
        '   ->   Lock timeout is now set to 550ms',
        '   -> Retrying now.',
        '   -> Retrying in 60 seconds...',
        '   ->   Increasing the lock timeout... Currently set to 550ms',
        '   ->   Lock timeout is now set to 775ms',
        '   -> Retrying now.',
        '   -> Retrying in 60 seconds...',
        '   ->   Increasing the lock timeout... Currently set to 775ms',
        '   ->   Lock timeout is now set to 1s',
        '   -> Retrying now.',
      ], calls[1..].map(&:first)
    end
  end

  def test_no_lock_timeout_increase_on_retry_if_disabled
    SafePgMigrations.config.lock_timeout = 0.1.seconds
    SafePgMigrations.config.increase_lock_timeout_on_retry = false

    calls = calls_for_lock_timeout_migration

    assert_equal [
      '   -> Retrying in 60 seconds...',
      '   -> Retrying now.',
      '   -> Retrying in 60 seconds...',
      '   -> Retrying now.',
      '   -> Retrying in 60 seconds...',
      '   -> Retrying now.',
      '   -> Retrying in 60 seconds...',
      '   -> Retrying now.',
    ], calls[1..].map(&:first)
  end

  def test_retry_if_lock_timeout
    calls = calls_for_lock_timeout_migration

    assert_equal [
      '   -> Retrying in 60 seconds...',
      '   -> Retrying now.',
      '   -> Retrying in 60 seconds...',
      '   -> Retrying now.',
    ], calls[1..4].map(&:first)
  end

  def test_statement_retry
    @migration = simulate_blocking_transaction_from_another_connection
    calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    assert @connection.column_exists?(:users, :email, :string)
    assert_equal [
      '== 8128 AddColumnWithBlockingTransactionFromAnotherConnection: migrating ======',
      '-- add_column(:users, :email, :string)',
      '   -> Lock timeout.',
      '   -> Statement was being blocked by the following query:',
      '   -> ',
    ], calls[0..4]
    assert_match(/\s*-> Query with pid \d+ started \d+ seconds? ago:\s*BEGIN; SELECT 1 FROM users/, calls[5])
    assert_equal [
      '   -> ',
      '   -> Retrying in 1 seconds...',
      '   -> Retrying now.',
    ], calls[7..9]
  end

  private

  def calls_for_lock_timeout_migration
    @migration = Class.new(ActiveRecord::Migration::Current) do
      def up
        connection.send(:retry_if_lock_timeout) do
          raise ActiveRecord::LockWaitTimeout, 'PG::LockNotAvailable: ERROR:  canceling statement due to lock timeout'
        end
      end
    end.new

    @connection.expects(:sleep).times(4)

    record_calls(@migration, :write) do
      run_migration
      flunk 'run_migration should raise'
    rescue StandardError => e
      assert_instance_of ActiveRecord::LockWaitTimeout, e.cause
      assert_includes e.cause.message, 'canceling statement due to lock timeout'
    end
  end
end
