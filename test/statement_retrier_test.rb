# frozen_string_literal: true

require 'test_helper'

class StatementRetrierTest < Minitest::Test
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

  def test_statement_retry
    @migration = simulate_blocking_transaction_from_another_connection
    calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    assert @connection.column_exists?(:users, :email, :string)
    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_column(:users, :email, :string)',
      '   -> Lock timeout.',
      '   -> Statement was being blocked by the following query:',
      '   -> ',
    ], calls[0..4]
    assert_match(/\s*-> transaction started \d+ seconds? ago:\s*BEGIN; SELECT 1 FROM users/, calls[5])
    assert_equal [
      '   -> ',
      '   -> Retrying in 1 seconds...',
      '   -> Retrying now.',
    ], calls[7..9]
  end
end
