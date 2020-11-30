# frozen_string_literal: true

require 'test_helper'

class IndexTest < MigrationTest
  def test_add_index
    connection.create_table(:users) { |t| t.string :email }
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_index(:users, :email)
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }
    assert_calls [
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
    ], calls

    run_migration migration, :down
    refute connection.index_exists?(:users, :email)
  end
end
