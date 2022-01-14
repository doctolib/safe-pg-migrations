# frozen_string_literal: true

require 'test_helper'

class BlockingActivityLoggerTest < Minitest::Test
  def test_blocking_activity_logger_filtered
    SafePgMigrations.config.blocking_activity_logger_verbose = false

    @migration = simulate_blocking_transaction_from_another_connection

    calls = record_calls(@migration, :write) { run_migration }.join
    assert_includes calls, 'lock type: relation'
    assert_includes calls, 'lock mode: AccessExclusiveLock'
    assert_includes calls, 'lock pid:'
    assert_includes calls, 'lock transactionid: null'
  end
end
