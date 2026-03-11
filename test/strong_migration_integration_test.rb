# frozen_string_literal: true

begin
  require 'strong_migrations'
rescue LoadError
  # strong_migrations not installed
end

require 'test_helper'

class StrongMigrationIntegrationTest < Minitest::Test
  def setup
    skip 'Strong migrations not installed' unless Object.const_defined? :StrongMigrations
    SafePgMigrations::StrongMigrationsIntegration.initialize

    super

    ENV.delete 'SAFETY_ASSURED'
  end

  def test_add_foreign_key_no_safety_assured_needed
    @connection.create_table(:users) { |t| t.bigint :password_id }
    @connection.create_table(:passwords) { |t| t.string :password }

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_foreign_key :users, :passwords
        end
      end.new

    run_migration
  end

  def test_add_column_no_safety_assured
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column :users, :name, :string
        end
      end.new

    run_migration
  end

  def test_add_column_with_volatile_default_and_backfill_raises
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column :users, :name, :string, default: lambda {
                                                        'NOW()'
                                                      }, null: false, default_value_backfill: :update_in_batches
        end
      end.new

    exception = assert_raises(StandardError, 'Dangerous operation detected #strong_migrations') { run_migration }
    assert_match(/Using default_value_backfill: :update_in_batches with volatile default/, exception.message)
    assert_match(/is not allowed/, exception.message)
    assert_match(/Volatile defaults \(like NOW\(\), clock_timestamp\(\), random\(\)\)/, exception.message)
  end

  def test_add_column_with_non_volatile_default_and_backfill_raises_without_safety_assured
    @connection.create_table(:users)
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          add_column :users, :status, :string,
                     default: 'active', null: false, default_value_backfill: :update_in_batches
        end
      end.new

    exception = assert_raises(StandardError, 'Dangerous operation detected #strong_migrations') { run_migration }
    assert_match(/default_value_backfill: :update_in_batches will take time/, exception.message)
  end

  def test_add_column_with_non_volatile_default_and_backfill_no_raise_with_safety_assured
    unless SafePgMigrations.get_pg_version_num(ActiveRecord::Base.connection) >= 120_000
      skip 'validate_check_constraint does not exist'
    end

    @connection.create_table(:users)
    @connection.execute('INSERT INTO users (id) VALUES (default);')

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          safety_assured do
            add_column :users, :status, :string,
                       default: 'active', null: false, default_value_backfill: :update_in_batches
          end
        end
      end.new

    run_migration

    assert @connection.column_exists?(:users, :status)
    assert_equal 'active', @connection.query_value('SELECT status FROM users LIMIT 1')
  end

  def test_rename_column_should_not_be_available_without_safety_assured
    @connection.create_table(:users) { |t| t.string :email }
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          rename_column :users, :email, :name
        end
      end.new

    assert_raises(StandardError, 'Dangerous operation detected #strong_migrations') { run_migration }
  end
end
