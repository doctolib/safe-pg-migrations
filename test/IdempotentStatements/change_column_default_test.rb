# frozen_string_literal: true

require_relative '../test_helper'

module IdempotentStatements
  class ChangeColumnDefaultTest < Minitest::Test
    def setup
      @plugins = SafePgMigrations::PLUGINS

      super

      @connection.create_table(:users) { |t| t.string :email, default: 'roger@email.com' }
      @connection.execute('INSERT INTO users (id) VALUES (default);')
    end

    def test_change_column_default_constant_same_value
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_default :users, :email, 'roger@email.com'
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }.map(&:first)

      assert_skipped_statement calls
    end

    def test_change_column_with_different_constant_value
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_default :users, :email, 'raimond@email.com'
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }.map(&:first)

      refute_skipped_statement calls
    end

    def test_change_column_with_reversible_migration
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_default :users, :email, from: 'roger@email.com', to: 'raimond@email.com'
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }.map(&:first)

      refute_skipped_statement calls
    end

    def test_change_column_with_reversible_migration_down
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_default :users, :email, to: 'roger@email.com', from: 'raimond@email.com'
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration(direction: :down) }.map(&:first)

      refute_skipped_statement calls
    end

    def test_change_column_default_to_function
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_default :users, :email, -> { 'CURRENT_TIMESTAMP' }
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }.map(&:first)

      refute_skipped_statement calls
    end

    def test_change_column_default_to_same_function
      @connection.change_column_default :users, :email, -> { 'CURRENT_TIMESTAMP' }

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_default :users, :email, -> { 'CURRENT_TIMESTAMP   ' }
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }.map(&:first)

      refute_skipped_statement calls
    end

    def test_change_column_default_to_different_function
      @connection.enable_extension 'pgcrypto' unless @connection.extension_enabled?('pgcrypto')
      @connection.change_column_default :users, :email, -> { 'gen_random_uuid()' }

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_default :users, :email, -> { 'CURRENT_TIMESTAMP   ' }
          end
        end.new

      calls = record_calls(@migration, :write) { run_migration }.map(&:first)

      refute_skipped_statement calls
    end

    private

    def assert_skipped_statement(calls)
      assert_calls_include calls, "-> /!\\ Column 'users.email' is already set to"
    end

    def refute_skipped_statement(calls)
      refute_calls_include calls, "-> /!\\ Column 'users.email' is already set to"
    end
  end
end
