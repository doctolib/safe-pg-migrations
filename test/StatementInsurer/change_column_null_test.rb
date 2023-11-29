# frozen_string_literal: true

require_relative '../test_helper'

module StatementInsurer
  class ChangeColumnNullTest < Minitest::Test
    def setup
      super

      @connection.create_table(:users) { |t| t.string :email, null: true }
      @connection.execute("INSERT INTO users (id, email) VALUES (default, 'roger@doctolib.com');")
    end

    def test_can_change_column_null_true
      @connection.change_column_null :users, :email, false

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_null(:users, :email, true)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      @connection.execute('INSERT INTO users (id) VALUES (default);') # should not pass if column not null failed

      assert_calls base_calls(action: 'DROP'), calls
    end

    def test_can_change_column_null_with_default
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_null(:users, :email, false, 'roger@doctolib.com')
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls base_calls(with_default: true), calls
    end

    def test_can_safely_change_column_null
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_null(:users, :email, false)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls met_requirements? ? safe_pg_calls : base_calls, calls
    end

    def test_when_constraint_already_exists_and_is_validated
      skip_if_unmet_requirements!

      # name is important otherwise generated name would match. Please keep the spaces in the constraint.
      @connection.add_check_constraint :users, 'email IS NOT      NULL', name: 'chk_email_is_not_null', validate: true

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_null(:users, :email, false)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls <<~CALLS.split("\n"), calls
        SET statement_timeout TO 0
        SET statement_timeout TO '5s'
        ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL
      CALLS
    end

    def test_when_constraint_already_exists_and_is_not_validated
      skip_if_unmet_requirements!

      # name is important otherwise generated name would match. Please keep the spaces in the constraint.
      @connection.add_check_constraint :users, 'email IS NOT      NULL', name: 'chk_email_is_not_null', validate: false

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_null(:users, :email, false)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls <<~CALLS.split("\n"), calls
        SET statement_timeout TO 0
        ALTER TABLE "users" VALIDATE CONSTRAINT "chk_email_is_not_null"
        SET statement_timeout TO '5s'
        ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL
      CALLS
    end

    private

    def safe_pg_calls
      [
        'ALTER TABLE "users" ADD CONSTRAINT chk_rails_8d5dc0bde6 CHECK (email IS NOT NULL) NOT VALID',
        'SET statement_timeout TO 0',
        'ALTER TABLE "users" VALIDATE CONSTRAINT "chk_rails_8d5dc0bde6"',
        "SET statement_timeout TO '5s'",
        'ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL',
        'ALTER TABLE "users" DROP CONSTRAINT "chk_rails_8d5dc0bde6"',
      ]
    end

    def base_calls(with_default: false, action: 'SET')
      [
        with_default ? "UPDATE \"users\" SET \"email\"='roger@doctolib.com' WHERE \"email\" IS NULL" : nil,
        "ALTER TABLE \"users\" ALTER COLUMN \"email\" #{action} NOT NULL",
      ].compact
    end

    def skip_if_unmet_requirements!
      return if met_requirements?

      skip "validate_check_constraint does not exist on ActiveRecord#{::ActiveRecord::VERSION::STRING}"
    end

    def met_requirements?
      Gem::Requirement.new('>6.1', '<7.2').satisfied_by?(Gem::Version.new(::ActiveRecord::VERSION::STRING)) &&
        SafePgMigrations.pg_version_num >= 120_000
    end
  end
end
