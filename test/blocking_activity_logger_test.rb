# frozen_string_literal: true

require 'test_helper'

class BlockingActivityLoggerTest < Minitest::Test
  def test_blocking_activity_logger_filtered
    SafePgMigrations.config.blocking_activity_logger_verbose = false

    @migration = simulate_blocking_transaction_from_another_connection

    calls = record_calls(@migration, :write) { run_migration }.join

    assert_match(/Query with pid \d+ started \d seconds? ago/, calls)
    assert_includes calls, 'lock type: relation'
    assert_includes calls, 'lock mode: AccessExclusiveLock'
    assert_includes calls, 'lock transactionid: null'
    refute_includes calls, 'BEGIN; SELECT 1 FROM users'
  end

  def test_doenot_fail_with_unknown_start_time
    @migration = simulate_blocking_transaction_from_another_connection

    alternate_connection = SafePgMigrations.alternate_connection
    SafePgMigrations.stubs(:alternate_connection).returns(alternate_connection)
    alternate_connection.stubs(:query).returns([[1234, 'SELECT something FROM a_table', nil]])

    calls = record_calls(@migration, :write) do
      run_migration
    end.join

    assert_match(/Query with pid 1234 started \(unknown start time\)/, calls)
  end

  def test_logger_unfiltered
    @migration = simulate_blocking_transaction_from_another_connection
    calls = record_calls(@migration, :write) { run_migration }.join

    assert_includes calls, '-- add_column(:users, :email, :string)'
    assert_includes calls, 'Lock timeout.'
    assert_includes calls, 'Statement was being blocked by the following query:'

    assert_match(/Query with pid \d+ started [01] seconds? ago/, calls)
    assert_includes calls, 'BEGIN; SELECT 1 FROM users'
    assert_includes calls, '   -> Retrying in 1 seconds...'
    assert_includes calls, '   -> Retrying now.'
  end

  def test_logger_unfiltered_sensitive_logger
    sensitive_logger = Minitest::Mock.new
    sensitive_logger.expect(:info, nil, ['Executing AddColumnWithBlockingTransactionFromAnotherConnection'])
    sensitive_logger.expect(:info, nil, ['add_column("users", :email, :string)'])
    sensitive_logger.expect(:info, nil) do |log|
      log.match?(/Query with pid \d+ started [01] seconds? ago:\s+BEGIN; SELECT 1 FROM users/)
    end

    SafePgMigrations.config.sensitive_logger = sensitive_logger

    @migration = simulate_blocking_transaction_from_another_connection
    calls = record_calls(@migration, :write) { run_migration }.join

    assert_includes calls, '-- add_column(:users, :email, :string)'
    assert_includes calls, 'Lock timeout.'
    assert_includes calls, 'Statement was being blocked by the following query:'
    assert_includes calls, 'Sensitive data sent to sensitive logger'
    assert_includes calls, '   -> Retrying in 1 seconds...'
    assert_includes calls, '   -> Retrying now.'

    refute_includes calls, 'BEGIN; SELECT 1 FROM users'
    refute_includes calls, 'Query with pid'

    sensitive_logger.verify
  end

  def test_add_index_unfiltered
    @migration = simulate_long_running_query_from_another_transaction
    calls = record_calls(@migration, :write) { run_migration }.join

    assert_includes calls,
                    'add_index("users", :email, {:algorithm=>:concurrently})'
    assert_includes calls, 'Statement was being blocked by the following query'
    assert_match(/Query with pid \d+ started 1 second ago: SELECT pg_sleep\(3\)/,
                 calls)
    assert_match(/Query with pid \d+ started 2 seconds ago: SELECT pg_sleep\(3\)/,
                 calls)
  end

  def test_add_index_filtered
    SafePgMigrations.config.blocking_activity_logger_verbose = false
    @migration = simulate_long_running_query_from_another_transaction

    calls = record_calls(@migration, :write) { run_migration }.join

    assert_includes calls,
                    'add_index("users", :email, {:algorithm=>:concurrently})'
    assert_includes calls, 'Statement was being blocked by the following query'

    variable_part_regex =
      /lock mode: ShareLock, lock transactionid: null/

    assert_match(Regexp.union(/Query with pid \d+ started 1 second ago: /, variable_part_regex), calls)
    assert_match(Regexp.union(/Query with pid \d+ started 2 seconds ago: /, variable_part_regex), calls)
  end
end
