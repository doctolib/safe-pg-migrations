# frozen_string_literal: true

require 'test_helper'

class StatementInsurerTest < Minitest::Test
  def test_add_column_before_pg_11_with_default_value
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column(:users, :admin, :boolean, default: false)
        end
      end.new

    SafePgMigrations.stub(:get_pg_version_num, 96_000) do
      execute_calls = nil
      write_calls =
        record_calls(@migration, :write) do
          execute_calls = record_calls(@connection, :execute) { run_migration }
        end
      assert_calls [
        # The column is added without any default.
        'ALTER TABLE "users" ADD "admin" boolean',

        # The default is added.
        'ALTER TABLE "users" ALTER COLUMN "admin" SET DEFAULT FALSE',
      ], execute_calls

      assert_equal [
        '== 8128 : migrating ===========================================================',
        '-- add_column(:users, :admin, :boolean, {:default=>false})',
        '   -> add_column("users", :admin, :boolean, {})',
        '   -> change_column_default("users", :admin, false)',
        '   -> backfill_column_default("users", :admin)',
      ], write_calls.map(&:first)[0...-3]
    end
  end

  def test_add_column_before_pg_11_without_null_or_default_value
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column(:users, :admin, :boolean)
        end
      end.new

    SafePgMigrations.stub(:get_pg_version_num, 96_000) do
      execute_calls = nil
      write_calls =
        record_calls(@migration, :write) do
          execute_calls = record_calls(@connection, :execute) { run_migration }
        end
      assert_calls [
        # The column is added without any default.
        'ALTER TABLE "users" ADD "admin" boolean',
      ], execute_calls

      assert_equal [
        '== 8128 : migrating ===========================================================',
        '-- add_column(:users, :admin, :boolean)',
      ], write_calls.map(&:first)[0...-3]
    end
  end

  def test_add_column_after_pg_11
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column(:users, :admin, :boolean, default: false, null: false)
        end
      end.new

    SafePgMigrations.stub(:get_pg_version_num, 110_000) do
      execute_calls = nil
      write_calls =
        record_calls(@migration, :write) do
          execute_calls = record_calls(@connection, :execute) { run_migration }
        end
      assert_calls [
        # The column is added with the default and not null constraint without any tricks
        'ALTER TABLE "users" ADD "admin" boolean DEFAULT FALSE NOT NULL',
      ], execute_calls

      assert_equal [
        '== 8128 : migrating ===========================================================',
        '-- add_column(:users, :admin, :boolean, {:default=>false, :null=>false})',
      ], write_calls.map(&:first)[0...-3]
    end
  end

  def test_change_column_with_timeout
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          change_column :users, :email, :text
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }

    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "users" ALTER COLUMN "email" TYPE text',
      "SET statement_timeout TO '70s'",
    ], calls
  end

  def test_add_belongs_to
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_belongs_to(:users, :user, foreign_key: true)
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
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

  def test_backfill_column_default
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          backfill_column_default(:users, :email)
        end
      end.new

    @connection.execute 'INSERT INTO users (id) values (GENERATE_SERIES(1, 5))'
    assert_equal 5, @connection.query_value('SELECT count(*) FROM users WHERE email IS NULL')

    SafePgMigrations.config.batch_size = 2
    @connection.change_column_default(:users, :email, 'michel@example.org')
    calls = record_calls(@connection, :execute) { run_migration }
    assert_equal 5, @connection.query_value("SELECT count(*) FROM users WHERE email = 'michel@example.org'")
    assert_calls [
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (1,2)',
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (3,4)',
      'UPDATE "users" SET "email" = DEFAULT WHERE id IN (5)',
    ], calls
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
end
