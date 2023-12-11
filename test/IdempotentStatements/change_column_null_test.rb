# frozen_string_literal: true

require_relative '../test_helper'

module IdempotentStatements
  class ChangeColumnNullTest < Minitest::Test
    def setup
      super

      skip_if_unmet_requirements

      @connection.create_table(:users) { |t| t.string :email, null: true }
      @connection.execute("INSERT INTO users (id, email) VALUES (default, 'roger@doctolib.com');")
    end

    def test_only_constraint
      @connection.add_check_constraint :users, 'email IS NOT NULL'

      @migration = migration
      execute_calls = nil
      write_calls = record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end

      assert_statement_skipped write_calls, execute_calls, constraint_creation
      assert_statement_skipped write_calls, execute_calls, constraint_validation
      assert_statement_executed write_calls, execute_calls, change_column_null_constraint
      assert_statement_executed write_calls, execute_calls, constraint_drop
    end

    def test_constraint_and_change_column
      @connection.add_check_constraint :users, 'email IS NOT NULL'
      @connection.change_column_null :users,
                                     :email,
                                     false,
                                     'default to skip constraint drop'

      @migration = migration
      execute_calls = nil
      write_calls = record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end

      assert_statement_skipped write_calls, execute_calls, constraint_creation
      assert_statement_skipped write_calls, execute_calls, constraint_validation
      assert_statement_skipped write_calls, execute_calls, change_column_null_constraint
      assert_statement_executed write_calls, execute_calls, constraint_drop
    end

    private

    def migration
      Class.new(ActiveRecord::Migration::Current) do
        def change
          change_column_null(:users, :email, false)
        end
      end.new
    end

    def skip_if_unmet_requirements
      return if SafePgMigrations.get_pg_version_num(ActiveRecord::Base.connection) >= 120_000

      skip "validate_check_constraint does not exist on ActiveRecord#{::ActiveRecord::VERSION::STRING}"
    end

    def assert_statement_skipped(write_calls, execute_calls, operation)
      refute_calls_include execute_calls, operation[:execute]
      assert_calls_include write_calls, operation[:write]
    end

    def assert_statement_executed(write_calls, execute_calls, operation)
      assert_calls_include execute_calls, operation[:execute]
      refute_calls_include write_calls, operation[:write]
    end

    def constraint_creation
      {
        execute: 'ALTER TABLE "users" ADD CONSTRAINT chk_rails_8d5dc0bde6 CHECK (email IS NOT NULL) NOT VALID',
        write: "   -> /!\\ Constraint 'chk_rails_8d5dc0bde6' already exists. Skipping statement.",
      }
    end

    def constraint_validation
      {
        execute: 'ALTER TABLE "users" VALIDATE CONSTRAINT "chk_rails_8d5dc0bde6"',
        write: "   -> /!\\ Constraint 'chk_rails_8d5dc0bde6' already validated. Skipping statement.",
      }
    end

    def change_column_null_constraint
      {
        execute: 'ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL',
        write: "   -> /!\\ Column 'users.email' is already set to 'null: false'. Skipping statement.",
      }
    end

    def constraint_drop
      {
        execute: 'ALTER TABLE "users" DROP CONSTRAINT "chk_rails_8d5dc0bde6"',
        write: "   -> /!\\ Constraint 'chk_rails_8d5dc0bde6' does not exist. Skipping statement.",
      }
    end
  end
end
