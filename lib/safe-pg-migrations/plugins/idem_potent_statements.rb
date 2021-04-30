# frozen_string_literal: true

module SafePgMigrations
  module IdemPotentStatements
    def add_index(table_name, column_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, index_column_names(column_name))
      return super unless index_name_exists?(table_name, index_name)

      return if index_valid?(index_name)

      remove_index(table_name, name: index_name)
      super
    end
    ruby2_keywords :add_index if respond_to?(:ruby2_keywords, true)

    def add_column(table_name, column_name, type, *)
      return super unless column_exists?(table_name, column_name)

      SafePgMigrations.say("/!\\ Column '#{column_name}' already exists in '#{table_name}'. Skipping statement.", true)
    end
    ruby2_keywords :add_column if respond_to?(:ruby2_keywords, true)

    def remove_column(table_name, column_name, type = nil, *)
      return super if column_exists?(table_name, column_name)

      SafePgMigrations.say("/!\\ Column '#{column_name}' not found on table '#{table_name}'. Skipping statement.", true)
    end
    ruby2_keywords :remove_column if respond_to?(:ruby2_keywords, true)

    def remove_index(table_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, options)

      return super if index_name_exists?(table_name, index_name)

      SafePgMigrations.say("/!\\ Index '#{index_name}' not found on table '#{table_name}'. Skipping statement.", true)
    end
    ruby2_keywords :remove_index if respond_to?(:ruby2_keywords, true)

    def add_foreign_key(from_table, to_table, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      suboptions = options.slice(:name, :column)
      return super unless foreign_key_exists?(from_table, suboptions.present? ? nil : to_table, **suboptions)

      SafePgMigrations.say(
        "/!\\ Foreign key '#{from_table}' -> '#{to_table}' already exists. Skipping statement.",
        true
      )
    end
    ruby2_keywords :add_foreign_key if respond_to?(:ruby2_keywords, true)

    def create_table(table_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      options.delete(:comment)
      return super if options[:force] || !table_exists?(table_name)

      SafePgMigrations.say "/!\\ Table '#{table_name}' already exists.", true

      td = create_table_definition(table_name, *args)

      yield td if block_given?

      SafePgMigrations.say(td.indexes.empty? ? '-- Skipping statement' : '-- Creating indexes', true)

      td.indexes.each do |column_name, index_options|
        add_index(table_name, column_name, **index_options)
      end
    end
    ruby2_keywords :create_table if respond_to?(:ruby2_keywords, true)

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
