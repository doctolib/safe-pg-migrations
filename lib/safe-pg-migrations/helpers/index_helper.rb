# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module IndexHelper
      def index_definition(table_name, column_name, **options)
        index_definition, = add_index_options(table_name, column_name, **options)
        index_definition
      end

      private

      def index_valid?(index_name)
        query_value <<~SQL.squish
          SELECT indisvalid
          FROM pg_index i
          JOIN pg_class c
            ON i.indexrelid = c.oid
          WHERE c.relname = '#{index_name}';
        SQL
      end
    end
  end
end
