# frozen_string_literal: true

require 'test_helper'

class SafePgMigrationsTest < MigrationTest
  def test_create_table
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          create_table(:users) do |t|
            t.string :email
            t.references :user, foreign_key: true
          end
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }
    assert_calls [
      "SET statement_timeout TO '5s'",

      # Create the table with constraints.
      'CREATE TABLE "users" ("id" bigserial primary key, "email" character varying, "user_id" bigint, ' \
        'CONSTRAINT "fk_rails_6d0b8b3c2f" FOREIGN KEY ("user_id") REFERENCES "users" ("id") )',

      # Create the index.
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '5s'",

      "SET statement_timeout TO '70s'",
    ], calls

    run_migration migration, :down
    refute connection.table_exists?(:users)
  end
end
