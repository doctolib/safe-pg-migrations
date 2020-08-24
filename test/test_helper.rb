# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'bundler/setup'

require 'minitest/autorun'
require 'mocha/setup'
require 'active_record'
require 'active_support'
require 'pry'

require 'safe-pg-migrations/base'

ENV['DATABASE_URL'] ||= 'postgres://postgres@localhost/safe_pg_migrations_test'

ActiveRecord::Base.logger = ActiveSupport::Logger.new('debug.log', 0, 100 * 1024 * 1024)
ActiveRecord::Base.establish_connection
ActiveRecord::InternalMetadata.create_table

ActiveRecord::Migration.prepend(SafePgMigrations::Migration)

class Minitest::Test
  DUMMY_MIGRATION_VERSION = 8128

  make_my_diffs_pretty!

  def run_migration(direction = :up)
    @migration.version = DUMMY_MIGRATION_VERSION
    ActiveRecord::Migrator.new(direction, [@migration]).migrate
  end

  def assert_calls(expected, actual)
    assert_equal [
      "SET lock_timeout TO '5s'",
      *expected,
      "SET lock_timeout TO '70s'",
    ], actual[0...-4].map(&:first).map(&:squish)
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
      }
    recorder.call
    yield
    calls
  ensure
    object.unstub(method)
  end
end
