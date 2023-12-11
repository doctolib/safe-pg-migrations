# frozen_string_literal: true

require_relative '../test_helper'

module StatementInsurer
  class AddCheckConstraintTest < Minitest::Test
    def setup
      super

      @connection.create_table(:users) { |t| t.string :email }
      @connection.execute("INSERT INTO users (id, email) VALUES (default, 'roger@doctolib.com');")
    end

    def test_can_add_check_constraint_without_validation
      @connection.execute('INSERT INTO users (id) VALUES (default);') # If validation, will make it fail

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_check_constraint(:users, 'email IS NOT NULL', validate: false)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        'ALTER TABLE "users" ADD CONSTRAINT chk_rails_8d5dc0bde6 CHECK (email IS NOT NULL) NOT VALID',
      ], calls
    end

    def test_can_add_check_constraint_with_validation
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_check_constraint(:users, 'email IS NOT NULL', validate: true)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        'ALTER TABLE "users" ADD CONSTRAINT chk_rails_8d5dc0bde6 CHECK (email IS NOT NULL) NOT VALID',
        'SET statement_timeout TO 0',
        'ALTER TABLE "users" VALIDATE CONSTRAINT "chk_rails_8d5dc0bde6"',
        "SET statement_timeout TO '5s'",
      ], calls
    end

    def test_can_add_check_constraint
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_check_constraint(:users, 'email IS NOT NULL')
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        'ALTER TABLE "users" ADD CONSTRAINT chk_rails_8d5dc0bde6 CHECK (email IS NOT NULL) NOT VALID',
        'SET statement_timeout TO 0',
        'ALTER TABLE "users" VALIDATE CONSTRAINT "chk_rails_8d5dc0bde6"',
        "SET statement_timeout TO '5s'",

      ], calls
    end
  end
end
