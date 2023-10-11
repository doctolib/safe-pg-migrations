# frozen_string_literal: true

require 'test_helper'

class UselessStatementLoggerTest < Minitest::Test
  def test_ddl_transactions
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        disable_ddl_transaction!
        # just to test the CI
        def change
          create_table(:users) { |t| t.string :email }
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.join("\n")

    assert_includes(
      write_calls,
      '/!\ No need to explicitly use `disable_ddl_transaction`, safe-pg-migrations does it for you'
    )
  end

  def test_no_warning_when_no_ddl_transaction
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          create_table(:users) { |t| t.string :email }
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.join("\n")

    refute_includes write_calls, '/!\ No need to explicitly disable DDL transaction, safe-pg-migrations does it for you'
  end

  def test_add_index_concurrently
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_index :users, :email, algorithm: :concurrently
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.join("\n")

    assert_includes(
      write_calls,
      '/!\ No need to explicitly use `algorithm: :concurrently`, safe-pg-migrations does it for you'
    )
  end

  def test_no_warning_when_no_index_concurrently
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_index :users, :email
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.join("\n")

    refute_includes(
      write_calls,
      '/!\ No need to explicitly use `algorithm: :concurrently`, safe-pg-migrations does it for you'
    )
  end

  def test_add_foreign_key_validate_false
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, validate: false
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.join("\n")

    assert_includes(
      write_calls,
      '/!\ No need to explicitly use `validate: :false`, safe-pg-migrations does it for you'
    )
  end

  def test_add_foreign_key_no_validation
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.join("\n")

    refute_includes(
      write_calls,
      '/!\ No need to explicitly use `validate: :false`, safe-pg-migrations does it for you'
    )
  end
end
