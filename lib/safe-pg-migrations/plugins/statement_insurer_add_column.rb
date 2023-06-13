# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurerAddColumn
    ruby2_keywords def add_column(table_name, column_name, type, *args)
      options = args.last.is_a?(Hash) && args.last
      options ||= {}

      if should_keep_default_implementation?(**options)
        with_setting(:statement_timeout, SafePgMigrations.config.pg_statement_timeout) { return super }
      end

      default = options.delete(:default)
      null = options.delete(:null)

      SafePgMigrations.say_method_call(:add_column, table_name, column_name, type, options)
      with_setting(:statement_timeout, SafePgMigrations.config.pg_statement_timeout) do
        super table_name, column_name, type, **options
      end

      if null == false
        SafePgMigrations.say_method_call(:change_column_default, table_name, column_name, default)
        change_column_default(table_name, column_name, default)
      end

      SafePgMigrations.say_method_call(:backfill_column_default, table_name, column_name)
      without_statement_timeout do
        backfill_column_default(table_name, column_name)
      end

      change_column_null(table_name, column_name, null) if null == false
    end

    private

    def should_keep_default_implementation?(default: nil, default_value_backfill: :auto, **)
      default_value_backfill == :auto || !default ||
        !SafePgMigrations::Helpers::SatisfiedHelper.satisfies_add_column_update_rows_backfill?
    end

    def backfill_column_default(table_name, column_name)
      model = Class.new(ActiveRecord::Base) { self.table_name = table_name }
      quoted_column_name = quote_column_name(column_name)

      model.in_batches(of: SafePgMigrations.config.backfill_batch_size).each do |relation|
        relation.update_all("#{quoted_column_name} = DEFAULT")
        sleep SafePgMigrations.config.backfill_pause
      end
    end
  end
end
