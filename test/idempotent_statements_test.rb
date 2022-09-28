# frozen_string_literal: true

require 'test_helper'

class IdempotentStatementsTest < Minitest::Test
  def test_create_table_idempotent
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          create_table :users do |t|
            t.string :email
          end
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.map(&:first)

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- create_table(:users)',
      "   -> /!\\ Table 'users' already exists.",
      '   -> -- Skipping statement',
    ], write_calls[0...4]
  end

  def test_add_column_idempotent
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { add_column :users, :name, :string }
        end
      end.new
    write_calls = record_calls(@migration, :write) { run_migration }.map(&:first)

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_column(:users, :name, :string)',
    ], write_calls[0...2]

    assert_equal [
      '-- add_column(:users, :name, :string)',
      "   -> /!\\ Column 'name' already exists in 'users'. Skipping statement.",
    ], write_calls[3..4]
  end

  def test_remove_column_idempotent
    @connection.create_table(:users) { |t| t.string :email, index: true }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { remove_column :users, :email }
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    refute @connection.index_exists?(:users, :email)

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- remove_column(:users, :email)',
    ], write_calls[0...2]

    assert_equal [
      '-- remove_column(:users, :email)',
      "   -> /!\\ Column 'email' not found on table 'users'. Skipping statement.",
    ], write_calls[3..4]

    assert_equal write_calls.length, 8
    refute @connection.index_exists?(:users, :email)
  end

  def test_remove_index_idempotent
    @connection.create_table(:users) { |t| t.string(:email, index: true) }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { remove_index :users, :email }
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }.map(&:first)
    refute @connection.index_exists?(:users, :email)

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- remove_index(:users, :email)',
      '   -> remove_index("users", {:column=>:email, :algorithm=>:concurrently})',
    ], write_calls[0...3]

    assert_equal [
      '-- remove_index(:users, :email)',
      '   -> remove_index("users", {:column=>:email, :algorithm=>:concurrently})',
      "   -> /!\\ Index 'index_users_on_email' not found on table 'users'. Skipping statement.",
    ], write_calls[4...7]

    assert_equal write_calls.length, 10
    refute @connection.index_exists?(:users, :email)
  end

  def test_add_index_idempotent
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { add_index(:users, :email, name: :my_custom_index_name, where: 'email IS NOT NULL') }
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }

    assert_calls [
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'CREATE INDEX CONCURRENTLY "my_custom_index_name" ON "users" ("email") WHERE email IS NOT NULL',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_add_index_invalid_index
    @connection.create_table(:users) { |t| t.string :email, index: true }

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_index(:users, :email)
        end
      end.new

    @connection.stubs(:index_valid?).returns(false)
    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',

      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'DROP INDEX CONCURRENTLY "index_users_on_email"',
      "SET lock_timeout TO '0'",
      "SET statement_timeout TO '0'",

      'CREATE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_create_index_name_fails_explicitly_if_invalid
    @connection.create_table(:users) { |t| t.string :email }

    my_name = :index_users_that_longer_than_64_characters_and_that_will_be_truncated_by_pg

    @connection.execute <<~SQL # Creating the index with a long name
      CREATE INDEX #{my_name}
      on users(email);
    SQL

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_index(:users, :name, name: :index_users_that_longer_than_64_characters_and_that_will_be_truncated_by_pg)
        end
      end.new

    assert_raises do
      run_migration
    end
  end

  def test_detects_name_conflicts_when_creating_an_index
    @connection.create_table(:users) do |t|
      t.string :email
      t.string :name
    end

    @connection.add_index :users, :name, name: 'index_on_users'

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_index(:users, :email, name: 'index_on_users')
        end
      end.new

    write_calls = record_calls(@migration, :write) { run_migration }

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- add_index(:users, :email, {:name=>"index_on_users"})',
      "   -> /!\\ Index 'index_on_users' already exists in 'users'. Skipping statement.",
    ], write_calls.map(&:first).values_at(0, 1, 3)
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

  def test_add_foreign_key_with_column_option
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

  def test_add_foreign_key_with_other_options
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

  def test_add_foreign_key_different_tables
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

  def test_create_table
    # Simulates an interruption between the table creation and the index creation
    @connection.create_table(:users) do |t|
      t.string :name, index: true
      t.string :email
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          create_table(:users) do |t|
            t.string :name, index: true
            t.string :email, index: true
          end
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    indexes = ActiveRecord::Base.connection.indexes :users
    refute_empty indexes
    assert_equal 'index_users_on_email', indexes.first.name

    refute_includes flat_calls(calls), 'CREATE INDEX CONCURRENTLY "index_users_on_name" ON "users" ("name")'

    assert_calls [
      "SET statement_timeout TO '5s'",
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '5s'",
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'CREATE INDEX "index_users_on_email" ON "users" ("email")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '5s'",
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_remove_foreign_key
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
      t.references :users, foreign_key: true, index: false
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { remove_foreign_key :messages, :users }
        end
      end.new

    execute_calls = nil
    write_calls =
      record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end

    assert_calls [
      'ALTER TABLE "messages" DROP CONSTRAINT "fk_rails_e3b11c0cbb"',
    ], execute_calls

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- remove_foreign_key(:messages, :users)',
      '-- remove_foreign_key(:messages, :users)',
      "   -> /!\\ Foreign key 'messages' -> 'users' does not exist. Skipping statement.",
    ], write_calls.map(&:first).values_at(0, 1, 3, 4)
  end

  def test_remove_foreign_key_using_to_table
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
      t.references :users, foreign_key: true, index: false
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          2.times { remove_foreign_key :messages, to_table: :users }
        end
      end.new

    execute_calls = nil
    write_calls =
      record_calls(@migration, :write) do
        execute_calls = record_calls(@connection, :execute) { run_migration }
      end

    assert_calls [
      'ALTER TABLE "messages" DROP CONSTRAINT "fk_rails_e3b11c0cbb"',
    ], execute_calls

    assert_equal [
      '== 8128 : migrating ===========================================================',
      '-- remove_foreign_key(:messages, {:to_table=>:users})',
      '-- remove_foreign_key(:messages, {:to_table=>:users})',
      "   -> /!\\ Foreign key 'messages' -> '{:to_table=>:users}' does not exist. Skipping statement.",
    ], write_calls.map(&:first).values_at(0, 1, 3, 4)
  end
end
