# frozen_string_literal: true

require_relative '../test_helper'

module StatementInsurer
  class ChangeColumnNullTest < Minitest::Test
    def setup
      super

      @connection.create_table(:users) { |t| t.string :email, null: true }
      @connection.execute('INSERT INTO users (id) VALUES (default);')
    end

    def test_can_change_column_null_true
      @connection.change_column_null :users, :email, false, 'roger@doctolib.com'

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_null(:users, :email, true)
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      @connection.execute('INSERT INTO users (id) VALUES (default);') # should not pass if column not null failed

      assert_calls [
        "SET statement_timeout TO '5s'",
        'ALTER TABLE "users" ALTER COLUMN "email" DROP NOT NULL',
        "SET statement_timeout TO '70s'",
      ], calls
    end

    def test_can_change_column_null_with_default
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            change_column_null(:users, :email, false, 'roger@doctolib.com')
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        "SET statement_timeout TO '5s'",
        "UPDATE \"users\" SET \"email\"='roger@doctolib.com' WHERE \"email\" IS NULL",
        'ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL',
        "SET statement_timeout TO '70s'",
      ], calls
    end
  end
end
