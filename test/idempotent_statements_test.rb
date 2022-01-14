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

  def test_add_index_idempotent_invalid_index
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
end
