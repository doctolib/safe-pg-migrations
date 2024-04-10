# frozen_string_literal: true

require_relative '../test_helper'

module StatementInsurer
  class RemoveColumnTest < Minitest::Test
    def test_can_remove_column_with_foreign_key
      @connection.create_table(:users)
      @connection.create_table(:passwords)
      @connection.add_reference(:users, :password, foreign_key: true)

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            remove_column(:users, :password_id)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls <<~CALLS.strip.split("\n"), calls
        ALTER TABLE "users" DROP CONSTRAINT "fk_rails_baad13daec"
        ALTER TABLE "users" DROP COLUMN "password_id"
      CALLS
    end

    def test_can_remove_column_with_foreign_key_on_other_column
      @connection.create_table(:users) { |t| t.string :name }
      @connection.create_table(:passwords)
      @connection.add_reference(:users, :password, foreign_key: true)

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            remove_column(:users, :name)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_equal ['ALTER TABLE "users" DROP COLUMN "name"'], calls[2]
    end

    def test_can_remove_column_without_foreign_key_or_index
      @connection.create_table(:users) { |t| t.string :name }

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            remove_column(:users, :name)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_equal ['ALTER TABLE "users" DROP COLUMN "name"'], calls[2]
    end

    def test_can_remove_column_with_index_on_other_columns
      @connection.create_table(:users) { |t| t.string :name, :email }
      @connection.add_index(:users, :email)

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            remove_column(:users, :name)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_equal ['ALTER TABLE "users" DROP COLUMN "name"'], calls[2]
    end

    def test_can_remove_column_with_dependent_index
      @connection.create_table(:users) { |t| t.string :name, :email }
      @connection.add_index(:users, :name)

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            remove_column(:users, :name)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_equal ['ALTER TABLE "users" DROP COLUMN "name"'], calls[2]
    end

    def test_can_not_remove_column_with_dependent_composite_index
      @connection.create_table(:users) { |t| t.string :name, :email }
      @connection.add_index(:users, %i[name email], name: 'index_users_on_name_and_email')

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            remove_column(:users, :name)
          end
        end.new

      error_message = <<~ERROR
        Cannot drop column name from table users because composite index(es): index_users_on_name_and_email is/are present.
        If they are still required, create the index(es) without name before dropping the existing index(es).
        Then you will be able to drop the column.
      ERROR

      exception = assert_raises(StandardError, error_message) { run_migration }
      assert_match error_message, exception.message
    end
  end
end
