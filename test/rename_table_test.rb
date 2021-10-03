# frozen_string_literal: true

require 'test_helper'

class RenameTableTest < Minitest::Test
  def setup
    SafePgMigrations.instance_variable_set(:@config, nil)
    @connection = ActiveRecord::Base.connection
    @verbose_was = ActiveRecord::Migration.verbose
    @connection.create_table(:schema_migrations) { |t| t.string :version }
    @connection.create_table(:foo) { |t| t.string :name }
    ActiveRecord::SchemaMigration.create_table
    ActiveRecord::Migration.verbose = false
    @connection.execute("SET statement_timeout TO '70s'")
    @connection.execute("SET lock_timeout TO '70s'")
  end

  def teardown
    ActiveRecord::SchemaMigration.drop_table
    @connection.execute('SET statement_timeout TO 0')
    @connection.execute("SET lock_timeout TO '30s'")
    @connection.drop_table(:foo, if_exists: true)
    ActiveRecord::Migration.verbose = @verbose_was
  end

  def test_rename_table
    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          rename_table(:foo, :bar)
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }

    assert_calls [
      'ALTER TABLE "foo" RENAME TO "bar"',
      'ALTER INDEX "foo_pkey" RENAME TO "bar_pkey"',
      'ALTER TABLE "public"."foo_id_seq" RENAME TO "bar_id_seq"',
      'CREATE VIEW "foo" AS SELECT * FROM "bar"',
      "COMMENT ON TABLE \"bar\" IS 'TODO: remove after the next deployment, superseded by \"bar\"'",
    ], calls

    @connection.exec_query('SELECT * FROM foo') # `table_exists?` won't work with a view
    assert @connection.table_exists?(:bar)

    run_migration(:down)
    assert @connection.table_exists?(:foo)
    refute @connection.table_exists?(:bar)
  end

  # def test_rename_table_with_disabled_ddl_transaction
  #   @migration =
  #     Class.new(ActiveRecord::Migration::Current) do
  #       disable_ddl_transaction!

  #       def change
  #         rename_table(:foo, :bar)
  #       end
  #     end.new

  #   begin
  #     run_migration
  #     flunk 'rename_table with a disable DDL transaction should fail'
  #   rescue => e
  #     assert_includes e.message, 'DDL transaction is disabled'
  #   end
  # end
end
