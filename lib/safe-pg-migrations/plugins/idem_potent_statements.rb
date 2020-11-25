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

    def add_column(table_name, column_name, type, options = {})
      return super unless column_exists?(table_name, column_name)

      SafePgMigrations.say("/!\\ Column '#{column_name}' already exists in '#{table_name}'. Skipping statement.", true)
    end

    def remove_column(table_name, column_name, type = nil, options = {})
      return super if column_exists?(table_name, column_name)

      SafePgMigrations.say("/!\\ Column '#{column_name}' not found on table '#{table_name}'. Skipping statement.", true)
    end

    def remove_index(table_name, options = {})
      index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, options)

      return super if index_name_exists?(table_name, index_name)

      SafePgMigrations.say("/!\\ Index '#{index_name}' not found on table '#{table_name}'. Skipping statement.", true)
    end

    def add_foreign_key(from_table, to_table, **options)
      options_or_to_table = options.slice(:name, :column).presence || to_table
      return super unless foreign_key_exists?(from_table, options_or_to_table)

      SafePgMigrations.say(
        "/!\\ Foreign key '#{from_table}' -> '#{to_table}' already exists. Skipping statement.",
        true
      )
    end

    def create_table(table_name, comment: nil, **options)
      return super if options[:force] || !table_exists?(table_name)

      SafePgMigrations.say "/!\\ Table '#{table_name}' already exists.", true

      td = create_table_definition(table_name, **options)

      yield td if block_given?

      SafePgMigrations.say(td.indexes.empty? ? 'Skipping statement' : 'Creating indexes', true)

      td.indexes.each do |column_name, index_options|
        add_index(table_name, column_name, index_options)
      end
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
