# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer
    module AddColumn
      def add_column(table_name, column_name, type, **options)
        return super if should_keep_default_implementation?(**options)

        options.delete(:default_value_backfill)

        raise <<~ERROR unless backfill_column_default_safe?(table_name)
          Table #{table_name} has more than #{SafePgMigrations.config.default_value_backfill_threshold} rows.
          Backfilling the default value for column #{column_name} on table #{table_name} would take too long.

          Please revert this migration, and backfill the default value manually.

          This check is configurable through the configuration "default_value_backfill_threshold".
        ERROR

        default = options.delete(:default)
        null = options.delete(:null)

        Helpers::Logger.say_method_call(:add_column, table_name, column_name, type, options)
        super(table_name, column_name, type, **options)

        Helpers::Logger.say_method_call(:change_column_default, table_name, column_name, default)
        change_column_default(table_name, column_name, default)

        backfill_column_default(table_name, column_name)

        change_column_null(table_name, column_name, null) if null == false
      end

      private

      def should_keep_default_implementation?(default: nil, default_value_backfill: :auto, **)
        default_value_backfill != :update_in_batches || !default ||
          !Helpers::SatisfiedHelper.satisfies_add_column_update_rows_backfill?
      end

      def backfill_column_default_safe?(table_name)
        return true if SafePgMigrations.config.default_value_backfill_threshold.nil?

        row, = query("SELECT reltuples AS estimate FROM pg_class where relname = '#{table_name}';")
        estimate, = row

        estimate <= SafePgMigrations.config.default_value_backfill_threshold
      end

      def backfill_column_default(table_name, column_name)
        model = Class.new(ActiveRecord::Base) { self.table_name = table_name }
        quoted_column_name = quote_column_name(column_name)

        Helpers::Logger.say_method_call(:backfill_column_default, table_name, column_name)

        Helpers::BatchOver.new(model).each_batch do |batch|
          batch.update_all("#{quoted_column_name} = DEFAULT")

          sleep SafePgMigrations.config.backfill_pause
        end
      end
    end
  end
end
