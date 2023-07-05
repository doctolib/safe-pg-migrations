# frozen_string_literal: true

require_relative '../test_helper'

module IdempotentStatements
  class AddColumnTest < Minitest::Test
    def setup
      super

      @connection.create_table(:appointments) { |t| t.string :email }
      @connection.create_table(:patients) { |t| t.string :email }
      @connection.create_table(:users) do |t|
        t.string :name
        t.references :appointment, foreign_key: true
        t.references :patient, foreign_key: true
      end

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            drop_table(:users)
          end
        end.new
    end

    def test_first_fk_already_removed
      @connection.remove_foreign_key(:users, name: 'fk_rails_253ea793f9')

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls <<~CALLS.strip.split("\n"), calls
        SET statement_timeout TO '5s'
        ALTER TABLE "users" DROP CONSTRAINT "fk_rails_d15efa01b1"
        SET statement_timeout TO '70s'
        SET statement_timeout TO '5s'
        DROP TABLE "users"
        SET statement_timeout TO '70s'
      CALLS
    end

    def test_fks_already_removed
      @connection.remove_foreign_key(:users, name: 'fk_rails_253ea793f9')
      @connection.remove_foreign_key(:users, name: 'fk_rails_d15efa01b1')

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls <<~CALLS.strip.split("\n"), calls
        SET statement_timeout TO '5s'
        DROP TABLE "users"
        SET statement_timeout TO '70s'
      CALLS
    end
  end
end
