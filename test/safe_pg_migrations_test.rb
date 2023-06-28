# frozen_string_literal: true

require 'test_helper'

class SafePgMigrationsTest < Minitest::Test
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
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ADD "email" character varying',
      "SET statement_timeout TO '70s'",
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ADD "user_id" bigint',
      "SET statement_timeout TO '70s'",

      # An index is created because of the column reference.
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET lock_timeout TO '4950ms'",
      "SET statement_timeout TO '70s'",
    ], calls

    run_migration(:down)
    refute @connection.column_exists?(:users, :email)
    refute @connection.column_exists?(:users, :user)
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
      'SET lock_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
      "SET lock_timeout TO '4950ms'",
      "SET statement_timeout TO '70s'",
    ], calls

    run_migration(:down)
    refute @connection.index_exists?(:users, :email)
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

  private

  def simulate_blocking_transaction_from_another_connection
    SafePgMigrations.config.retry_delay = 1.second
    SafePgMigrations.config.safe_timeout = 0.5.second
    SafePgMigrations.config.blocking_activity_logger_margin = 0.1.seconds

    @connection.create_table(:users)

    Class.new(ActiveRecord::Migration::Current) do
      def up
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
  end
end
