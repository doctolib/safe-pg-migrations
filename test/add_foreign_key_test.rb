# frozen_string_literal: true

require 'test_helper'

class AddForeignKeyTest < MiniTest::Test
  DUMMY_MIGRATION_VERSION = 8128

  def setup
    SafePgMigrations.instance_variable_set(:@config, nil)
    @connection = ActiveRecord::Base.connection
    @verbose_was = ActiveRecord::Migration.verbose
    @connection.create_table(:schema_migrations) { |t| t.string :version }
    ActiveRecord::SchemaMigration.create_table
    ActiveRecord::Migration.verbose = false
    @connection.execute("SET statement_timeout TO '70s'")
    @connection.execute("SET lock_timeout TO '70s'")
  end

  def teardown
    ActiveRecord::SchemaMigration.drop_table
    @connection.execute('SET statement_timeout TO 0')
    @connection.execute("SET lock_timeout TO '30s'")
    @connection.drop_table(:messages, if_exists: true)
    @connection.drop_table(:conversations, if_exists: true)
    @connection.drop_table(:users, if_exists: true)
    ActiveRecord::Migration.verbose = @verbose_was
  end

  def test_add_foreign_key_with_validate_explicitly_false
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, validate: false
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_273a25a7a6" FOREIGN KEY ("user_id") ' \
      'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_add_foreign_key
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
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
    @connection.create_table(:users, id: false) do |t|
      t.string :email
      t.bigint :real_id, primary_key: true
      t.bigint :other_id
    end
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :author_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, primary_key: :real_id, column: :author_id, name: :message_user_key
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
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

  def test_add_foreign_key_idem_potent
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { add_foreign_key :messages, :users }
        end
      end.new

    execute_calls = nil
    write_calls =
      record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end
    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_273a25a7a6" FOREIGN KEY ("user_id") ' \
      'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_273a25a7a6"',
      "SET statement_timeout TO '70s'",
      "SET statement_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_273a25a7a6"',
      "SET statement_timeout TO '70s'",
    ], execute_calls

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_foreign_key(:messages, :users)',
      '-- add_foreign_key(:messages, :users)',
      "   -> /!\\ Foreign key 'messages' -> 'users' already exists. Skipping statement.",
    ], write_calls.map(&:first).values_at(0, 1, 3, 4)
  end

  def test_add_foreign_key_idem_potent_with_column_option
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :author_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { add_foreign_key :messages, :users, column: :author_id }
        end
      end.new

    execute_calls = nil
    write_calls =
      record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end

    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_995937c106" FOREIGN KEY ("author_id") ' \
      'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_995937c106"',
      "SET statement_timeout TO '70s'",
      "SET statement_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_995937c106"',
      "SET statement_timeout TO '70s'",
    ], execute_calls

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_foreign_key(:messages, :users, {:column=>:author_id})',
      '-- add_foreign_key(:messages, :users, {:column=>:author_id})',
      "   -> /!\\ Foreign key 'messages' -> 'users' already exists. Skipping statement.",
    ], write_calls.map(&:first).values_at(0, 1, 3, 4)
  end

  def test_add_foreign_key_idem_potent_with_other_options
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users
          add_foreign_key :messages, :users, on_delete: :cascade
        end
      end.new

    execute_calls = nil
    write_calls =
      record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end

    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_273a25a7a6" FOREIGN KEY ("user_id") ' \
      'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_273a25a7a6"',
      "SET statement_timeout TO '70s'",
      "SET statement_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_273a25a7a6"',
      "SET statement_timeout TO '70s'",
    ], execute_calls

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_foreign_key(:messages, :users)',
      '-- add_foreign_key(:messages, :users, {:on_delete=>:cascade})',
      "   -> /!\\ Foreign key 'messages' -> 'users' already exists. Skipping statement.",
    ], write_calls.map(&:first).values_at(0, 1, 3, 4)
  end

  def test_add_foreign_key_idem_potent_different_tables
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:conversations) { |t| t.string :subject }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :author_id
      t.bigint :conversation_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, column: :author_id
          add_foreign_key :messages, :conversations
        end
      end.new

    execute_calls = nil
    write_calls =
      record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end

    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_995937c106" FOREIGN KEY ("author_id") ' \
      'REFERENCES "users" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_995937c106"',
      "SET statement_timeout TO '70s'",
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_7f927086d2" FOREIGN KEY ("conversation_id") ' \
      'REFERENCES "conversations" ("id") NOT VALID',
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'ALTER TABLE "messages" VALIDATE CONSTRAINT "fk_rails_7f927086d2"',
      "SET statement_timeout TO '70s'",
    ], execute_calls

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_foreign_key(:messages, :users, {:column=>:author_id})',
      '-- add_foreign_key(:messages, :conversations)',
    ], write_calls.map(&:first).values_at(0, 1, 3)
  end

  def test_add_foreign_key_with_validation
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, validate: true
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_273a25a7a6" FOREIGN KEY ("user_id") REFERENCES "users" ("id")',
      "SET statement_timeout TO '70s'",
    ], calls
  end
end
