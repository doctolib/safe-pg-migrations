# frozen_string_literal: true

require_relative '../test_helper'

module StatementInsurer
  class AddIndexTest < Minitest::Test
    def setup
      super
    end

    def test_can_add_an_index_on_a_non_partitioned_table
      @connection.execute <<~SQL.squish
      CREATE TABLE IF NOT EXISTS bars (
        id SERIAL PRIMARY KEY,
        column_name VARCHAR(255)
      );
      SQL

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_index :bars, :column_name
          end
        end.new
      calls = record_calls(@connection, :execute) { run_migration }

      calls.flatten.include? 'CREATE INDEX CONCURRENTLY "index_bars_on_column_name" ON "bars" ("column_name")'

      indexes = @connection.execute "SELECT * FROM pg_indexes WHERE tablename = 'bars';"
      assert indexes.to_a.pluck('indexname').include? 'index_bars_on_column_name'

    end

    def test_can_add_an_index_on_a_partitioned_table
      # Create a partioned table partioned by created_at without partman
      @connection.execute <<~SQL.squish
      CREATE TABLE IF NOT EXISTS foos (
        id SERIAL PRIMARY KEY,
        column_name VARCHAR(255)
      ) Partition by RANGE (id);
      SQL

      # create partition for foos on id <1000000
      @connection.execute <<~SQL.squish
      CREATE TABLE IF NOT EXISTS foos_p1000000 PARTITION OF foos FOR VALUES FROM (MINVALUE) TO (1000000);
      CREATE TABLE IF NOT EXISTS foos_p2000000 PARTITION OF foos FOR VALUES FROM (1000001) TO (2000000);
      SQL


      query = "SELECT pg_inherits.inhrelid::regclass::text FROM pg_tables INNER JOIN pg_inherits ON pg_tables.tablename::regclass = pg_inherits.inhparent::regclass WHERE pg_tables.schemaname = current_schema() AND pg_tables.tablename = 'foo'"
      tables = @connection.execute query
      child_tables = tables.pluck('inhrelid')

      indexes = @connection.execute "SELECT * FROM pg_indexes WHERE tablename = 'foos';"
      indexes.to_a.pluck('indexname').include?('foos_column_name_idx') == []

      child_tables.each do |child_table|
        indexes = @connection.execute "SELECT * FROM pg_indexes WHERE tablename = '#{child_table}';"
        assert_equal indexes.to_a.pluck('indexname').include?("#{child_table}_column_name_idx"),  []
      end

      @migration =
        Class.new(ActiveRecord::Migration::Current) do
          def change
            add_index :foos, :column_name
          end
        end.new
      calls = record_calls(@connection, :execute) { run_migration }

      indexes = @connection.execute "SELECT * FROM pg_indexes WHERE tablename = 'foos';"
      assert indexes.to_a.pluck('indexname').include? 'foos_column_name_idx'

      child_tables.each do |child_table|
        indexes = @connection.execute "SELECT * FROM pg_indexes WHERE tablename = '#{child_table}';"
        assert indexes.to_a.pluck('indexname').include? " #{child_table}_column_name_idx"
      end
    end
  end
end



