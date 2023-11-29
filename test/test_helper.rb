# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'bundler/setup'

require 'minitest/autorun'
require 'mocha/minitest'
require 'active_record'
require 'active_support'
require 'pry'
require 'safe-pg-migrations/base'

ENV['POSTGRES_USER'] ||= ENV.fetch('USER', nil)
ENV['POSTGRES_DB'] ||= 'safe_pg_migrations_test'
ENV['DATABASE_URL'] ||= "postgres://#{ENV.fetch('POSTGRES_USER', nil)}@localhost/#{ENV.fetch('POSTGRES_DB', nil)}"

ActiveRecord::Base.logger = ActiveSupport::Logger.new('debug.log', 0, 100 * 1024 * 1024)

ActiveRecord::Migration.prepend(SafePgMigrations::Migration)
ActiveRecord::Migration.singleton_class.prepend(SafePgMigrations::Migration::ClassMethods)

class Minitest::Test
  DUMMY_MIGRATION_VERSION = 8128

  make_my_diffs_pretty!

  def setup
    ENV['SAFETY_ASSURED'] = '1'
    ActiveRecord::Base.establish_connection
    SafePgMigrations.instance_variable_set(:@config, nil)
    @verbose_was = ActiveRecord::Migration.verbose
    @connection = ActiveRecord::Base.connection
    @connection.tables.each { |table| @connection.drop_table table, force: :cascade }
    ActiveRecord::SchemaMigration.new(@connection).create_table
    ActiveRecord::InternalMetadata.new(@connection).create_table
    ActiveRecord::Migration.verbose = false
    @connection.execute("SET statement_timeout TO '70s'")
    @connection.execute("SET lock_timeout TO '70s'")
  end

  def teardown
    @connection ||= ActiveRecord::Base.connection

    @connection.tables.each { |table| @connection.drop_table table, force: :cascade }
    @connection.execute("SET statement_timeout TO '70s'")
    @connection.execute("SET lock_timeout TO '70s'")
    ActiveRecord::Migration.verbose = @verbose_was
    ActiveRecord::Base.connection_handler.clear_all_connections!
  end

  def run_migration(direction = :up)
    @migration.version = DUMMY_MIGRATION_VERSION

    migrator =
      if Gem::Requirement.new('>=6.0.0').satisfied_by?(Gem::Version.new(::ActiveRecord::VERSION::STRING))
        ActiveRecord::Migrator.new(direction, [@migration], ActiveRecord::SchemaMigration.new(@connection),
                                   ActiveRecord::InternalMetadata.new(@connection))
      else
        ActiveRecord::Migrator.new(direction, [@migration])
      end
    migrator.migrate
  end

  def assert_calls(expected, actual)
    assert_equal [
      "SET lock_timeout TO '4950ms'",
      "SET statement_timeout TO '5s'",
      *expected,
      "SET statement_timeout TO '70s'",
      "SET lock_timeout TO '70s'",
    ], flat_calls(actual)
  end

  def flat_calls(calls)
    calls.map(&:first).map(&:squish).reverse.drop_while { |call| %w[BEGIN COMMIT].include? call }.reverse
  end

  def assert_calls_include(calls, call)
    assert_includes calls.join("\n"), call
  end

  def refute_calls_include(calls, call)
    refute_includes calls.join("\n"), call
  end

  # Records method calls on an object. Behaves like a test spy.
  #
  # Example usage:
  #
  #   record_calls(foo, :bar) { foo.bar(1, 2); foo.bar(3, 4) }
  #
  # Example return:
  #
  #   [[1, 2], [3, 4]]
  #
  def record_calls(object, method)
    calls = []
    recorder =
      lambda {
        if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7')
          object.stubs(method).with do |*args, **kwargs|
            calls << (args + (kwargs.empty? ? [] : [kwargs]))
            # Temporarily unstub the method so that we can call the original method.
            object.unstub(method)
            begin
              # Call the original method.
              object.send(method, *args, **kwargs)
            ensure
              # Register the recorder again.
              recorder.call
            end
            true
          end
        else
          object.stubs(method).with do |*args|
            calls << args
            # Temporarily unstub the method so that we can call the original method.
            object.unstub(method)
            begin
              # Call the original method.
              object.send(method, *args)
            ensure
              # Register the recorder again.
              recorder.call
            end
            true
          end
        end
      }
    recorder.call
    yield
    calls
  ensure
    object.unstub(method)
  end

  def simulate_blocking_transaction_from_another_connection
    SafePgMigrations.config.retry_delay = 1.second
    SafePgMigrations.config.safe_timeout = 0.5.second
    SafePgMigrations.config.blocking_activity_logger_margin = 0.1.seconds

    @connection.create_table(:users)

    Class.new(ActiveRecord::Migration::Current) do
      def self.name
        'AddColumnWithBlockingTransactionFromAnotherConnection'
      end

      def up
        thread_lock = Concurrent::CountDownLatch.new
        thread =
          Thread.new do
            ActiveRecord::Base.connection.execute('BEGIN; SELECT 1 FROM users')
            thread_lock.count_down
            sleep 1
            ActiveRecord::Base.connection.commit_db_transaction
          end

        thread_lock.wait # Wait for the above transaction to start.

        add_column :users, :email, :string

        thread.join
      end
    end.new
  end

  def simulate_long_running_query_from_another_transaction
    SafePgMigrations.config.retry_delay = 1.second

    @connection.create_table(:users) do |t|
      t.string :email
    end

    Class.new(ActiveRecord::Migration::Current) do
      def up
        thread =
          Thread.new do
            ActiveRecord::Base.connection.execute('SELECT pg_sleep(3);')
          end

        sleep 0.1

        add_index :users, :email

        thread.join
      end
    end.new
  end
end
