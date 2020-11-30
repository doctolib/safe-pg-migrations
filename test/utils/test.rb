# frozen_string_literal: true

class MiniTest::Test
  DUMMY_MIGRATION_VERSION = 8128

  make_my_diffs_pretty!

  def setup
    SafePgMigrations.instance_variable_set(:@config, nil)
    @verbose_was = ActiveRecord::Migration.verbose
    connection.create_table(:schema_migrations) { |t| t.string :version }
    ActiveRecord::SchemaMigration.create_table
    ActiveRecord::Migration.verbose = false
    connection.execute("SET statement_timeout TO '70s'")
    connection.execute("SET lock_timeout TO '70s'")
  end

  def teardown
    ActiveRecord::SchemaMigration.drop_table
    connection.execute('SET statement_timeout TO 0')
    connection.execute("SET lock_timeout TO '30s'")
    drop_all_tables
    ActiveRecord::Migration.verbose = @verbose_was
  end

  private

  def connection
    @connection ||= ActiveRecord::Base.connection
  end

  def drop_all_tables
    connection.tables
      .reject { |t| t == 'ar_internal_metadata' }
      .each { |t| connection.drop_table t, if_exists: true, force: :cascade }
  end
end
