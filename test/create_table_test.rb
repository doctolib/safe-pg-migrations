# frozen_string_literal: true

require 'test_helper'

class SafePgMigrationsTest < Minitest::Test
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
    @connection.drop_table(:users, if_exists: true)
    ActiveRecord::Migration.verbose = @verbose_was
  end

  def test_create_table
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          create_table(:users) do |t|
            t.string :email
            t.references :user, foreign_key: true
          end
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      "SET statement_timeout TO '5s'",

      # Create the table with constraints.
      'CREATE TABLE "users" ("id" bigserial primary key, "email" character varying, "user_id" bigint, ' \
        'CONSTRAINT "fk_rails_6d0b8b3c2f" FOREIGN KEY ("user_id") REFERENCES "users" ("id") )',

      # Create the index.
      'SET statement_timeout TO 0',
      'SET lock_timeout TO 0',
      'CREATE INDEX "index_users_on_user_id" ON "users" ("user_id")',
      "SET lock_timeout TO '5s'",
      "SET statement_timeout TO '5s'",

      "SET statement_timeout TO '70s'",
    ], calls

    run_migration(:down)
    refute @connection.table_exists?(:users)
  end

  def test_create_table_idempotence
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
end
