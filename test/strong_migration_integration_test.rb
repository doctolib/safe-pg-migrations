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

  def test_add_column_without_safety_assured_and_backfill_in_batches_raises
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
    assert_equal <<~EXCEPTION, exception.message
      An error has occurred, all later migrations canceled:


      === Custom check #strong_migrations ===

      default_value_backfill: :update_in_batches will take time if the table is too big.

      Your configuration sets a pause of 0.5 seconds between batches of
      100000 rows. Each batch execution will take time as well. Please
      check that the estimated duration of the migration is acceptable
      before adding `safety_assured`.

    EXCEPTION
  end

  def test_add_column_with_safety_assured_and_backfill_in_batches_no_raise
    @connection.create_table(:users)

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def up
          safety_assured do
            add_column :users,
                       :name, :string, default: -> { 'NOW()' }, null: false, default_value_backfill: :update_in_batches
          end
        end
      end.new

    run_migration
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
