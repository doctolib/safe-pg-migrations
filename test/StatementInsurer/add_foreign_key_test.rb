# frozen_string_literal: true

require 'test_helper'

class AddForeignKeyTest < MigrationTest
  def test_add_foreign_key_with_validate_explicitly_false
    connection.create_table(:users) { |t| t.string :email }
    connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, validate: false
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }
    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_273a25a7a6" FOREIGN KEY ("user_id") ' \
      'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_add_foreign_key
    connection.create_table(:users) { |t| t.string :email }
    connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }
    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_273a25a7a6" FOREIGN KEY ("user_id") ' \
      'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_273a25a7a6"',
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_add_foreign_key_with_options
    connection.create_table(:users, id: false) do |t|
      t.string :email
      t.bigint :real_id, primary_key: true
      t.bigint :other_id
    end
    connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :author_id
    end

    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, primary_key: :real_id, column: :author_id, name: :message_user_key
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }
    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "message_user_key" FOREIGN KEY ("author_id") ' \
      'REFERENCES "users" ("real_id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "message_user_key"',
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_add_foreign_key_with_validation
    connection.create_table(:users) { |t| t.string :email }
    connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, validate: true
        end
      end.new

    calls = record_calls(connection, :execute) { run_migration migration }
    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_273a25a7a6" FOREIGN KEY ("user_id") REFERENCES "users" ("id")',
      "SET statement_timeout TO '70s'",
    ], calls
  end
end
