# frozen_string_literal: true

module SafePgMigrations
  module IdempotentStatements
    include Helpers::IndexHelper

    ruby2_keywords def add_index(table_name, column_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      index_definition = index_definition(table_name, column_name, **options)

      return super unless index_name_exists?(index_definition.table, index_definition.name)

      if index_valid?(index_definition.name)
        log_message("/!\\ Index '#{index_definition.name}' already exists in '#{table_name}'. Skipping statement.")
        return
      end

      remove_index(table_name, name: index_definition.name)
      super
    end

    ruby2_keywords def add_column(table_name, column_name, type, *)
      if column_exists?(table_name, column_name) && !column_exists?(table_name, column_name, type)
        error_message = "/!\\ Column '#{column_name}' already exists in '#{table_name}' with a different type"
        raise error_message
      end

      return super unless column_exists?(table_name, column_name, type)

      log_message("/!\\ Column '#{column_name}' already exists in '#{table_name}' with the same type (#{type}). Skipping statement.")
    end

    ruby2_keywords def remove_column(table_name, column_name, type = nil, *)
      return super if column_exists?(table_name, column_name)
      log_message("/!\\ Column '#{column_name}' not found on table '#{table_name}'. Skipping statement.")
    end

    ruby2_keywords def remove_index(table_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, options)

      return super if index_name_exists?(table_name, index_name)
      log_message("/!\\ Column '#{column_name}' not found on table '#{table_name}'. Skipping statement.")
    end

    ruby2_keywords def add_foreign_key(from_table, to_table, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      sub_options = options.slice(:name, :column)
      return super unless foreign_key_exists?(from_table, sub_options.present? ? nil : to_table, **sub_options)

      log_message("/!\\ Foreign key '#{from_table}' -> '#{to_table}' already exists. Skipping statement.")
    end

    def remove_foreign_key(from_table, to_table = nil, **options)
      return super if foreign_key_exists?(from_table, to_table, **options)

      reference_name = to_table || options[:to_table] || options[:column] || options[:name]
      log_message("/!\\ Foreign key '#{from_table}' -> '#{reference_name}' does not exist. Skipping statement.")
    end

    ruby2_keywords def create_table(table_name, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      return super if options[:force] || !table_exists?(table_name)

      Helpers::Logger.say "/!\\ Table '#{table_name}' already exists.", sub_item: true

      td = create_table_definition(table_name, *args)

      yield td if block_given?

      Helpers::Logger.say td.indexes.empty? ? '-- Skipping statement' : '-- Creating indexes', sub_item: true

      td.indexes.each do |column_name, index_options|
        add_index(table_name, column_name, **index_options)
      end
    end

    def add_check_constraint(table_name, expression, **options)
      constraint_definition = check_constraint_for table_name,
                                                   **check_constraint_options(table_name, expression, options)

      return super if constraint_definition.nil?

      log_message("/!\\ Constraint '#{constraint_definition.name}' already exists. Skipping statement.")
    end

    def change_column_null(table_name, column_name, null, *)
      column = column_for(table_name, column_name)

      return super if column.null != null

      log_message("/!\\ Column '#{table_name}.#{column.name}' is already set to 'null: #{null}'. Skipping statement.")
    end

    def validate_check_constraint(table_name, **options)
      constraint_definition = check_constraint_for!(table_name, **options)

      return super unless constraint_definition.validated?

      log_message("/!\\ Constraint '#{constraint_definition.name}' already validated. Skipping statement.")
    end

    def change_column_default(table_name, column_name, default_or_changes)
      column = column_for(table_name, column_name)
      previous_alter_statement = change_column_default_for_alter(table_name, column_name, column.default)
      new_alter_statement = change_column_default_for_alter(table_name, column_name, default_or_changes)

      # NOTE: PG change_column_default is already idempotent.
      # We try to detect it because it still takes an ACCESS EXCLUSIVE lock

      return super if new_alter_statement != previous_alter_statement

      log_message("/!\\ Column '#{table_name}.#{column.name}' is already set to 'default: #{column.default}'. Skipping statement.")
    end

    ruby2_keywords def drop_table(table_name, *)
      return super if table_exists?(table_name)

      log_message("/!\\ Table '#{table_name} does not exist. Skipping statement.")
    end

    private

    def log_message(message)
      Helpers::Logger.say <<~MESSAGE.squish, sub_item: true
        #{message}
      MESSAGE
    end
  end
end
