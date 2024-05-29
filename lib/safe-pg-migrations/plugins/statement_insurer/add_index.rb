# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer
    module AddIndex

      def add_index(table_name, column_name, **options)

        return super if table_is_not_partitioned?(table_name)

        return add_index_on_all_partitions(table_name, column_name)
      end

      def table_is_not_partitioned?(table_name)
        query = "SELECT inhrelid::regclass AS child_table FROM pg_inherits WHERE inhparent = '#{table_name}'::regclass;";
        result = ActiveRecord::Base.connection.exec_query query;
        result.to_a.empty?
      end

      def attach_child_index(child_index, parent_index)
        ActiveRecord::Base.connection.exec_query "ALTER INDEX #{parent_index} ATTACH PARTITION #{child_index}"
      end

      def child_tables(table_name)
        query = "SELECT pg_inherits.inhrelid::regclass::text FROM pg_tables INNER JOIN pg_inherits ON pg_tables.tablename::regclass = pg_inherits.inhparent::regclass WHERE pg_tables.schemaname = current_schema() AND pg_tables.tablename = '#{table_name}'"
        tables = ActiveRecord::Base.connection.exec_query query
        tables.pluck('inhrelid')
      end

      def add_index_on_all_partitions(table_name, column_names)
        # add_index method accepts a singular column_name or an array of columns
        column_names = [column_names] unless column_names.is_a?(Array)
        # Add index on parent table non concurrently
        parent_index_name = "#{table_name}_#{column_names.join('_')}_idx"
        ActiveRecord::Base.connection.exec_query "CREATE INDEX IF NOT EXISTS #{parent_index_name} ON #{table_name} (#{column_names.join(', ')});"

        child_tables(table_name).each do |child_table|
          # Add index on each child table concurrently
          child_index_name = "#{child_table}_#{column_names.join('_')}_idx"
          ActiveRecord::Base.connection.exec_query "CREATE INDEX CONCURRENTLY IF NOT EXISTS #{child_index_name} ON #{child_table} (#{column_names.join(', ')});"
          # Attach child index to parent index
          attach_child_index(child_index_name, parent_index_name)
        end
      end
    end
  end
end

