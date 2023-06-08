# frozen_string_literal: true

require_relative '../test_helper'

module IdempotentStatements
  class ValidateCheckConstraintTest < Minitest::Test
    def setup
      skip_if_unmet_requirements
      super

      @connection.create_table(:users) { |t| t.string :email }
      @connection.execute "INSERT INTO users (id, email) VALUES (default, 'stan@doctolib.com');"
    end

    def test_when_really_new
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_check_constraint :users, 'email IS NOT NULL', name: 'new_constraint'
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }

      refute_skipping_creation calls
      refute_skipping_validation calls
    end

    def test_when_completely_created
      @connection.add_check_constraint :users, 'email IS NOT NULL', name: 'new_constraint'

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_check_constraint(:users, 'email IS NOT NULL', name: 'new_constraint')
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }

      assert_skipping_creation calls
      assert_skipping_validation calls
    end

    def test_when_created_but_not_validated
      @connection.add_check_constraint :users, 'email IS NOT NULL', name: 'new_constraint', validate: false

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_check_constraint :users, 'email IS NOT NULL', name: 'new_constraint'
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }

      assert_skipping_creation calls
      refute_skipping_validation calls
    end

    def test_when_created_not_validated_with_validate_option_to_false
      @connection.add_check_constraint :users, 'email IS NOT NULL', name: 'new_constraint', validate: false

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_check_constraint :users, 'email IS NOT NULL', name: 'new_constraint', validate: false
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }

      assert_skipping_creation calls
      refute_skipping_validation calls
    end

    def test_when_created_not_validated_with_validate_option_to_true
      @connection.add_check_constraint :users, 'email IS NOT NULL', name: 'new_constraint', validate: false

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_check_constraint :users, 'email IS NOT NULL', name: 'new_constraint', validate: true
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }

      assert_skipping_creation calls
      refute_skipping_validation calls
    end

    private

    def assert_skipping_creation(calls)
      assert_call calls, "/!\\ Constraint 'new_constraint' already exists. Skipping statement."
    end

    def refute_skipping_creation(calls)
      refute_call calls, "/!\\ Constraint 'new_constraint' already exists. Skipping statement."
    end

    def assert_skipping_validation(calls)
      assert_call calls, "/!\\ Constraint 'new_constraint' already validated. Skipping statement."
    end

    def refute_skipping_validation(calls)
      refute_call calls, "/!\\ Constraint 'new_constraint' already validated. Skipping statement."
    end

    def assert_call(calls, call)
      assert_includes calls.join("\n"), call
    end

    def refute_call(calls, call)
      refute_includes calls.join("\n"), call
    end

    def skip_if_unmet_requirements
      return if Gem::Requirement.new('>6.1').satisfied_by?(Gem::Version.new(::ActiveRecord::VERSION::STRING))

      skip "validate_check_constraint does not exist on ActiveRecord#{::ActiveRecord::VERSION::STRING}"
    end
  end
end
