# frozen_string_literal: true

require_relative '../test_helper'

module StatementInsurer
  class AddColumnTest < Minitest::Test
    def setup
      @plugins = SafePgMigrations::PLUGINS

      super

      @connection.create_table(:users)
      @connection.execute('INSERT INTO users (id) VALUES (default);')

      SafePgMigrations.config.backfill_pause = 0.01.seconds
    end

    def teardown
      super

      SafePgMigrations.send :remove_const, :PLUGINS
      SafePgMigrations.const_set(:PLUGINS, @plugins)
    end

    def test_add_column_with_default_and_null_specified
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def up
            add_column(:users, :admin, :boolean, default: false, null: false)
          end
        end.new

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

    def test_can_add_column_without_default
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        'ALTER TABLE "users" ADD "email" character varying',
      ], calls
    end

    def test_can_add_column_no_algorithm_specified
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: '', null: false
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        "ALTER TABLE \"users\" ADD \"email\" character varying DEFAULT '' NOT NULL",

      ], calls
    end

    def test_can_add_column_auto_algorithm_specified
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: '', null: false, default_value_backfill: :auto
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        "ALTER TABLE \"users\" ADD \"email\" character varying DEFAULT '' NOT NULL",

      ], calls
    end

    def test_uses_auto_algorithm_when_unmet_requirements
      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: '', null: false, default_value_backfill: :auto
          end
        end.new

      calls = nil

      SafePgMigrations::Helpers::SatisfiedHelper.stub :satisfies_add_column_update_rows_backfill?, false do
        calls = record_calls(@connection, :execute) { run_migration }
      end

      assert_calls [
        "ALTER TABLE \"users\" ADD \"email\" character varying DEFAULT '' NOT NULL",

      ], calls
    end

    def test_with_default_value_backfill_algorithm
      skip_if_unmet_requirements!

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: 'roger@doctolib.com', null: false,
                                                default_value_backfill: :update_in_batches
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        'ALTER TABLE "users" ADD "email" character varying',
        "ALTER TABLE \"users\" ALTER COLUMN \"email\" SET DEFAULT 'roger@doctolib.com'",
        # exec_calls goes here
        'ALTER TABLE "users" ADD CONSTRAINT chk_rails_8d5dc0bde6 CHECK (email IS NOT NULL) NOT VALID',
        'SET statement_timeout TO 0',
        'ALTER TABLE "users" VALIDATE CONSTRAINT "chk_rails_8d5dc0bde6"',
        "SET statement_timeout TO '5s'",
        'ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL',
        'ALTER TABLE "users" DROP CONSTRAINT "chk_rails_8d5dc0bde6"',
      ], calls
    end

    def test_with_default_value_backfill_algorithm_and_null_true
      skip_if_unmet_requirements!

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: 'roger@doctolib.com', null: true,
                                                default_value_backfill: :update_in_batches
          end
        end.new

      calls = record_calls(@connection, :execute) { run_migration }

      assert_calls [
        'ALTER TABLE "users" ADD "email" character varying',
        "ALTER TABLE \"users\" ALTER COLUMN \"email\" SET DEFAULT 'roger@doctolib.com'",
        # exec_calls goes here
      ], calls
    end

    def test_backfill_in_multiple_steps
      skip_if_unmet_requirements!

      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')

      SafePgMigrations.config.backfill_batch_size = 3

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: 'roger@doctolib.com', null: false,
                                                default_value_backfill: :update_in_batches
          end
        end.new

      calls = record_calls(@connection, :update) { run_migration }

      assert_equal 3, calls.count
      assert_equal 8, @connection.query_value("SELECT count(*) FROM users WHERE email = 'roger@doctolib.com'")
    end

    def test_sleeps_between_backfills
      skip_if_unmet_requirements!

      # BlockingActivityLogger also calls sleep, it's harder to test
      new_plugins = SafePgMigrations::PLUGINS - [SafePgMigrations::BlockingActivityLogger]
      SafePgMigrations.send :remove_const, :PLUGINS
      SafePgMigrations.const_set(:PLUGINS, new_plugins)

      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')

      SafePgMigrations.config.backfill_batch_size = 2

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: 'roger@doctolib.com', null: false,
                                                default_value_backfill: :update_in_batches
          end
        end.new

      @connection.expects(:sleep).twice.with(SafePgMigrations.config.backfill_pause)
      run_migration
    end

    def test_with_uuid_as_key
      skip_if_unmet_requirements!

      @connection.enable_extension 'pgcrypto' unless @connection.extension_enabled?('pgcrypto')
      @connection.drop_table :users
      @connection.create_table(:users, id: :uuid, force: true)

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def up
            add_column :users, :email, :string, default: 'roger@doctolib.com', null: false,
                                                default_value_backfill: :update_in_batches
          end
        end.new

      5.times do
        @connection.execute 'INSERT INTO users (id) values (default)'
      end

      SafePgMigrations.config.backfill_batch_size = 2

      calls = record_calls(@connection, :update) { run_migration }

      assert_equal 3, calls.count
      assert_equal 5, @connection.query_value("SELECT count(*) FROM users WHERE email = 'roger@doctolib.com'")
    end

    def test_raises_if_default_value_backfill_and_too_big_table
      skip_if_unmet_requirements!
      SafePgMigrations.config.default_value_backfill_threshold = 4

      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('INSERT INTO users (id) VALUES (default);')
      @connection.execute('VACUUM users;') # update size estimation, otherwise it would be 0

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_column :users, :email, :string, default: 'roger@doctolib.com', null: false,
                                                default_value_backfill: :update_in_batches
          end
        end.new

      assert_raises(StandardError, 'Table users has more than 4 rows') { run_migration }
    end

    private

    def skip_if_unmet_requirements!
      if Gem::Requirement.new('>6.1').satisfied_by?(Gem::Version.new(::ActiveRecord::VERSION::STRING)) &&
         SafePgMigrations.get_pg_version_num(ActiveRecord::Base.connection) >= 120_000
        return
      end

      skip "validate_check_constraint does not exist on ActiveRecord#{::ActiveRecord::VERSION::STRING}"
    end
  end
end
