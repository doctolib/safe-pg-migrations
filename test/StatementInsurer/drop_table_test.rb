# frozen_string_literal: true

require_relative '../test_helper'

module StatementInsurer
  class DropTableTest < Minitest::Test
    def test_can_drop_table_without_foreign_keys
      @connection.create_table(:users) { |t| t.string :email }

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            drop_table(:users)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls <<~CALLS.strip.split("\n"), calls
        DROP TABLE "users"
      CALLS
    end

    def test_can_drop_table_with_foreign_key
      @connection.create_table(:appointments) { |t| t.string :email }
      @connection.create_table(:users) do |t|
        t.string :email
        t.references :appointment, foreign_key: true
      end

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            drop_table(:users)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls <<~CALLS.strip.split("\n"), calls
        ALTER TABLE "users" DROP CONSTRAINT "fk_rails_253ea793f9"
        DROP TABLE "users"
      CALLS
    end

    def test_can_drop_table_with_several_foreign_keys
      @connection.create_table(:appointments) { |t| t.string :email }
      @connection.create_table(:patients) { |t| t.string :email }
      @connection.create_table(:users) do |t|
        t.string :email
        t.references :appointment, foreign_key: true
        t.references :patient, foreign_key: true
      end

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            drop_table(:users)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls <<~CALLS.strip.split("\n"), calls
        ALTER TABLE "users" DROP CONSTRAINT "fk_rails_253ea793f9"
        ALTER TABLE "users" DROP CONSTRAINT "fk_rails_d15efa01b1"
        DROP TABLE "users"
      CALLS
    end
  end
end
