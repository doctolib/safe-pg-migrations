# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer
    include Helpers::SessionSettingManagement
    include AddColumn
    include ChangeColumnNull

    def validate_check_constraint(table_name, **options)
      Helpers::Logger.say_method_call :validate_check_constraint, table_name, **options
      without_statement_timeout { super }
    end

    def add_check_constraint(table_name, expression, **options)
      Helpers::SatisfiedHelper.satisfies_add_check_constraints!
      return unless supports_check_constraints?

      options = check_constraint_options(table_name, expression, options)

      Helpers::Logger.say_method_call :add_check_constraint, table_name, expression, **options,
        validate: false
      super table_name, expression, **options, validate: false

      return unless options.fetch(:validate, true)

      validate_check_constraint table_name, name: options[:name]
    end

    def validate_foreign_key(*, **)
      without_statement_timeout { super }
    end

    def add_foreign_key(from_table, to_table, **options)
      validate_present = options.key?(:validate)
      options[:validate] = false unless validate_present

      super(from_table, to_table, **options)

      return if validate_present

      sub_options = options.slice(:name, :column)
      validate_foreign_key from_table, sub_options.present? ? nil : to_table, **sub_options
    end

    def create_table(table_name, **options)
      super do |td|
        yield td if block_given?
        td.indexes.map! do |key, index_options|
          index_options[:algorithm] ||= :default
          [key, index_options]
        end
      end
    end

    def add_index(table_name, column_name, **options)
      if options[:algorithm] == :default
        options.delete :algorithm
      else
        options[:algorithm] = :concurrently
      end

      Helpers::Logger.say_method_call(:add_index, table_name, column_name, **options)
      without_timeout { super(table_name, column_name, **options) }
    end

    def remove_index(table_name, column_name = nil, **options)
      options[:algorithm] = :concurrently unless options.key?(:algorithm)

      Helpers::Logger.say_method_call(:remove_index, table_name, column_name, **options)
      without_timeout { super(table_name, column_name, **options) }
    end

    def remove_column(table_name, column_name, type = nil, **options)
      foreign_key = foreign_key_for(table_name, column: column_name)

      remove_foreign_key(table_name, name: foreign_key.name) if foreign_key
      super
    end

    def drop_table(table_name, **options)
      foreign_keys(table_name).each do |foreign_key|
        remove_foreign_key(table_name, name: foreign_key.name)
      end

      Helpers::Logger.say_method_call :drop_table, table_name, **options

      super
    end
  end
end
