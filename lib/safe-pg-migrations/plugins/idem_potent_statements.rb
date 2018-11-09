# frozen_string_literal: true

module SafePgMigrations
  module IdemPotentStatements
    def add_index(table_name, column_name, **options)
      index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, index_column_names(column_name))
      return super unless index_name_exists?(table_name, index_name)

      return if index_valid?(index_name)

      remove_index(table_name, name: index_name)
      super
    end

    def remove_column(table_name, column_name, **options)
      return super if column_exists?(table_name, column_name)
      SafePgMigrations.say("/!\\ Column '#{column_name}' not found in table '#{table_name}'", true)
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
