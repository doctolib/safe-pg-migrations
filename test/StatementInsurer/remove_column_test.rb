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

    def test_can_remove_column_without_foreign_key
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
  end
end
