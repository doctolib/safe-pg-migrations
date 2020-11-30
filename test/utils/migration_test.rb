# frozen_string_literal: true

class MigrationTest < Minitest::Test
  def run_migration(migration, direction = :up)
    migration.version = DUMMY_MIGRATION_VERSION
    ActiveRecord::Migrator.new(direction, [migration], ActiveRecord::SchemaMigration).migrate
  end

  def assert_calls(expected, actual)
    assert_equal [
      "SET lock_timeout TO '5s'",
      *expected,
      "SET lock_timeout TO '70s'",
    ], flat_calls(actual)
  end

  def flat_calls(calls)
    calls.map(&:first).map(&:squish).reverse.drop_while { |call| %w[BEGIN COMMIT].include? call }.reverse
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
