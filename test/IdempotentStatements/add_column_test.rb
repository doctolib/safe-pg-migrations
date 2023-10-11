# frozen_string_literal: true

require_relative '../test_helper'

module IdempotentStatements
  class AddColumnTest < Minitest::Test
    def setup
      @plugins = SafePgMigrations::PLUGINS

      super

      @connection.create_table(:users)
      @connection.execute('INSERT INTO users (id) VALUES (default);')

      SafePgMigrations.config.backfill_pause = 0.01.seconds
    end

    def test_add_column_no_options
      @connection.add_column :users, :email, :string

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string
          end
        end.new
      calls = record_calls(@migration, :write) { run_migration }.map(&:first)

      assert_calls_include calls, add_column_creation_skipped_call
    end

    def test_column_already_created
      skip_if_unmet_requirements!

      @connection.add_column :users, :email, :string

      calls = record_calls(migration, :write) { run_migration }.map(&:first)

      assert_calls_include calls, add_column_creation_skipped_call
      refute_calls_include calls, change_column_default_skipped_call
      refute_calls_include calls, change_column_null_skipped_call
    end

    def test_column_already_created_with_a_different_type
      skip_if_unmet_requirements!

      @connection.add_column :users, :status, :string
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :status, :boolean
          end
        end.new

      error = assert_raises StandardError do
        record_calls(@migration, :write) { run_migration }
      end
      expected_error_message = "/!\\ Column 'status' already exists in 'users' with a different type"
      assert_includes error.message, expected_error_message
    end

    def test_column_after_change_column_default
      skip_if_unmet_requirements!

      @connection.add_column :users, :email, :string
      @connection.change_column_default :users, :email, 'roger@doctolib.com'

      calls = record_calls(migration, :write) { run_migration }.map(&:first)

      assert_calls_include calls, add_column_creation_skipped_call
      assert_calls_include calls, change_column_default_skipped_call
      refute_calls_include calls, change_column_null_skipped_call
    end

    private

    def migration
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: 'roger@doctolib.com', null: false,
                                                default_value_backfill: :update_in_batches
          end
        end.new
    end

    def add_column_creation_skipped_call
      "/!\\ Column 'email' already exists in 'users' with the same type (string). Skipping statement."
    end

    def change_column_default_skipped_call
      "/!\\ Column 'users.email' is already set to 'default: roger@doctolib.com'. Skipping statement"
    end

    def change_column_null_skipped_call
      "   -> /!\\ Column 'users.email' is already set to 'null: false'. Skipping statement."
    end

    def skip_if_unmet_requirements!
      if Gem::Requirement.new('>6.1').satisfied_by?(Gem::Version.new(::ActiveRecord::VERSION::STRING)) &&
         SafePgMigrations.get_pg_version_num(ActiveRecord::Base.connection) >= 120_000
        return
      end

      skip "validate_check_constraint does not exist on ActiveRecord#{::ActiveRecord::VERSION::STRING}"
    end
  end
end
