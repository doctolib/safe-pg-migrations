# frozen_string_literal: true

require_relative '../test_helper'

module StatementInsurer
  class StatementInsurerTest < Minitest::Test
    def setup
      skip_if_unmet_requirements
      super

      @connection.create_table(:users) { |t| t.string :email }
      @connection.execute("INSERT INTO users (id, email) VALUES (default, 'stan@doctolib.com');")
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
        "SET statement_timeout TO '70s'",
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
        "SET statement_timeout TO '70s'",
      ], calls
    end

    def skip_if_unmet_requirements
      return if Gem::Requirement.new('>6.1').satisfied_by?(Gem::Version.new(::ActiveRecord::VERSION::STRING))

      skip "validate_check_constraint does not exist on ActiveRecord#{::ActiveRecord::VERSION::STRING}"
    end
  end
end
