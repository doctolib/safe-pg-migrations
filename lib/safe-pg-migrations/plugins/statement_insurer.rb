# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer # rubocop:disable Metrics/ModuleLength
    include AddColumn

    def validate_check_constraint(table_name, **options)
      Helpers::Logger.say_method_call :validate_check_constraint, table_name, **options
      without_statement_timeout do
        super
      end
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

    ruby2_keywords def add_foreign_key(from_table, to_table, *args)
      options = args.last.is_a?(Hash) ? args.last : {}
      validate_present = options.key?(:validate)
      options[:validate] = false unless validate_present

      super(from_table, to_table, **options)

      return if validate_present

      sub_options = options.slice(:name, :column)
      validate_foreign_key from_table, sub_options.present? ? nil : to_table, **sub_options
    end

    ruby2_keywords def create_table(*)
      super do |td|
        yield td if block_given?
        td.indexes.map! do |key, index_options|
          index_options[:algorithm] ||= :default
          [key, index_options]
        end
      end
    end

    ruby2_keywords def add_index(table_name, column_name, *args_options)
      options = args_options.last.is_a?(Hash) ? args_options.last : {}

      if options[:algorithm] == :default
        options.delete :algorithm
      else
        options[:algorithm] = :concurrently
      end

      Helpers::Logger.say_method_call(:add_index, table_name, column_name, **options)
      without_timeout { super(table_name, column_name, **options) }
    end

    ruby2_keywords def remove_index(table_name, *args)
      options = args.last.is_a?(Hash) ? args.last : { column: args.last }
      options[:algorithm] = :concurrently unless options.key?(:algorithm)

      Helpers::Logger.say_method_call(:remove_index, table_name, **options)
      without_timeout { super(table_name, **options) }
    end

    def change_column_null(table_name, column_name, null, default = nil)
      return super if default || null || !Helpers::SatisfiedHelper.satisfies_change_column_null_requirements?

      add_check_constraint table_name, "#{column_name} IS NOT NULL"

      Helpers::Logger.say_method_call :change_column_null, table_name, column_name, false
      super table_name, column_name, false

      Helpers::Logger.say_method_call :remove_check_constraint, table_name, "#{column_name} IS NOT NULL"
      remove_check_constraint table_name, "#{column_name} IS NOT NULL"
    end

    def remove_column(table_name, column_name, *)
      foreign_key = foreign_key_for(table_name, column: column_name)

      with_setting(:statement_timeout, SafePgMigrations.config.pg_statement_timeout) do
        remove_foreign_key(table_name, name: foreign_key.name) if foreign_key
        super
      end
    end

    ruby2_keywords def drop_table(table_name, *args)
      foreign_keys(table_name).each do |foreign_key|
        with_setting(:statement_timeout, SafePgMigrations.config.pg_statement_timeout) do
          remove_foreign_key(table_name, name: foreign_key.name)
        end
      end

      Helpers::Logger.say_method_call :drop_table, table_name, *args

      with_setting(:statement_timeout, SafePgMigrations.config.pg_statement_timeout) do
        super(table_name, *args)
      end
    end

    def with_setting(key, value)
      old_value = query_value("SHOW #{key}")
      execute("SET #{key} TO #{quote(value)}")
      begin
        yield
      ensure
        begin
          execute("SET #{key} TO #{quote(old_value)}")
        rescue ActiveRecord::StatementInvalid => e
          # Swallow `PG::InFailedSqlTransaction` exceptions so as to keep the
          # original exception (if any).
          raise unless e.cause.is_a?(PG::InFailedSqlTransaction)
        end
      end
    end

    def without_statement_timeout(&block)
      with_setting(:statement_timeout, 0, &block)
    end

    def without_lock_timeout(&block)
      with_setting(:lock_timeout, 0, &block)
    end

    def without_timeout(&block)
      without_statement_timeout { without_lock_timeout(&block) }
    end
  end
end
