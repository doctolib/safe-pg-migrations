# frozen_string_literal: true

module SafePgMigrations
  module IdempotentStatements
    ruby2_keywords def add_index(table_name, column_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}

      index_definition = index_definition(table_name, column_name, **options)

      return super unless index_name_exists?(index_definition.table, index_definition.name)

      if index_valid?(index_definition.name)
        SafePgMigrations.say(
          "/!\\ Index '#{index_definition.name}' already exists in '#{table_name}'. Skipping statement.",
          true
        )
        return
      end

      remove_index(table_name, name: index_definition.name)
      super
    end

    ruby2_keywords def add_column(table_name, column_name, type, *)
      return super unless column_exists?(table_name, column_name)

      SafePgMigrations.say("/!\\ Column '#{column_name}' already exists in '#{table_name}'. Skipping statement.", true)
    end

    ruby2_keywords def remove_column(table_name, column_name, type = nil, *)
      return super if column_exists?(table_name, column_name)

      SafePgMigrations.say("/!\\ Column '#{column_name}' not found on table '#{table_name}'. Skipping statement.", true)
    end

    ruby2_keywords def remove_index(table_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, options)

      return super if index_name_exists?(table_name, index_name)

      SafePgMigrations.say("/!\\ Index '#{index_name}' not found on table '#{table_name}'. Skipping statement.", true)
    end

    ruby2_keywords def add_foreign_key(from_table, to_table, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      suboptions = options.slice(:name, :column)
      return super unless foreign_key_exists?(from_table, suboptions.present? ? nil : to_table, **suboptions)

      SafePgMigrations.say(
        "/!\\ Foreign key '#{from_table}' -> '#{to_table}' already exists. Skipping statement.",
        true
      )
    end

    def remove_foreign_key(from_table, to_table = nil, **options)
      return super if foreign_key_exists?(from_table, to_table, **options)

      reference_name = to_table || options[:to_table] || options[:column] || options[:name]
      SafePgMigrations.say(
        "/!\\ Foreign key '#{from_table}' -> '#{reference_name}' does not exist. Skipping statement.",
        true
      )
    end

    ruby2_keywords def create_table(table_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      return super if options[:force] || !table_exists?(table_name)

      SafePgMigrations.say "/!\\ Table '#{table_name}' already exists.", true

      td = create_table_definition(table_name, *args)

      yield td if block_given?

      SafePgMigrations.say(td.indexes.empty? ? '-- Skipping statement' : '-- Creating indexes', true)

      td.indexes.each do |column_name, index_options|
        add_index(table_name, column_name, **index_options)
      end
    end

    def add_check_constraint(table_name, expression, **options)
      constraint_definition = check_constraint_for table_name,
                                                   **check_constraint_options(table_name, expression, options)

      return super if constraint_definition.nil?

      SafePgMigrations.say "/!\\ Constraint '#{constraint_definition.name}' already exists. Skipping statement.", true
    end

    def change_column_null(table_name, column_name, null)
      column = column_for(table_name, column_name)

      return super if column.null != null

      SafePgMigrations.say(
        "/!\\ Column '#{table_name}.#{column.name}' is already set to 'null: #{null}'. Skipping statement.",
        true
      )
    end

    def validate_check_constraint(table_name, **options)
      constraint_definition = check_constraint_for!(table_name, **options)

      return super unless constraint_definition.validated?

      SafePgMigrations.say "/!\\ Constraint '#{constraint_definition.name}' already validated. Skipping statement.",
                           true
    end

    protected

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
