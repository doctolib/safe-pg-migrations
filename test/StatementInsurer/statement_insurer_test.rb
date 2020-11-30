# frozen_string_literal: true

require 'test_helper'

class StatementInsurerTest < MigrationTest
  def test_change_column_with_timeout
    connection.create_table(:users) { |t| t.string :email }
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          change_column :users, :email, :text
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }

    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ALTER COLUMN "email" TYPE text',
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_add_belongs_to
    connection.create_table(:users)
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_belongs_to(:users, :user, foreign_key: true)
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }
    assert_calls [
      # The column is added.
      'ALTER TABLE "users" ADD "user_id" bigint',

      # The index is created concurrently.
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "index_users_on_user_id" ON "users" ("user_id")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",

      # The foreign key is added.
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ADD CONSTRAINT "fk_rails_6d0b8b3c2f" FOREIGN KEY ("user_id") ' \
        'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "users" VALIDATE CONSTRAINT "fk_rails_6d0b8b3c2f"',
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_with_setting_inside_a_failed_transaction
    migration =
      Class.new(ActiveRecord::Migration::Current) do
        disable_ddl_transaction!

        def up
          transaction do
            with_setting(:statement_timeout, '1s') do
              execute('boom!')
            end
          end
        end
      end.new

    begin
      run_migration migration
      flunk 'run_migration should raise'
    rescue StandardError => e
      assert_instance_of ActiveRecord::StatementInvalid, e.cause
      assert_includes e.cause.message, 'boom!'
    end
  end
end
