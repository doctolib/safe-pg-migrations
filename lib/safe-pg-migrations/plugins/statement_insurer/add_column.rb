# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer
    module AddColumn
      def add_column(table_name, column_name, type, **options)
        return super if should_keep_default_implementation?(**options)

        options.delete(:default_value_backfill)

        default = options[:default]

        # Raise if using automatic backfill with a volatile default
        raise_on_volatile_default(table_name, column_name, default) if volatile_default?(default)

        raise <<~ERROR unless backfill_column_default_safe?(table_name)
          Table #{table_name} has more than #{SafePgMigrations.config.default_value_backfill_threshold} rows.
          Backfilling the default value for column #{column_name} on table #{table_name} would take too long.

          Please revert this migration, and backfill the default value manually.

          This check is configurable through the configuration "default_value_backfill_threshold".
        ERROR

        default = options.delete(:default)
        null = options.delete(:null)

        Helpers::Logger.say_method_call(:add_column, table_name, column_name, type, options)
        super

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

        batch_handler = lambda do |batch|
          batch.update_all("#{quoted_column_name} = DEFAULT")

          sleep SafePgMigrations.config.backfill_pause
        end

        backfill_batch_size = SafePgMigrations.config.backfill_batch_size

        if ActiveRecord.version >= Gem::Version.new('8.1')
          model.in_batches(of: backfill_batch_size, use_ranges: true).each(&batch_handler)
        else
          Helpers::BatchOver.new(model, of: backfill_batch_size).each_batch(&batch_handler)
        end
      end

      def volatile_default?(default)
        Helpers::VolatileDefault.volatile_default?(default)
      end

      def raise_on_volatile_default(table_name, column_name, default)
        default_display = default.is_a?(Proc) ? '<Proc>' : default

        raise <<~ERROR
          Using default_value_backfill: :update_in_batches with volatile default '#{default_display}'
          on #{table_name}.#{column_name} is not allowed.

          Volatile defaults are non-deterministic functions like gen_random_uuid(), now(), or clock_timestamp().
          They are evaluated per row and can cause migrations to hang for a very long time on large tables.
          You should backfill them "manually" with proper monitoring and control.

          Split the operation into multiple steps in this EXACT order:

          1. ALTER COLUMN SET DEFAULT (for new and updated rows)
             change_column_default :#{table_name}, :#{column_name}, '#{default_display}'
          2. ADD CONSTRAINT CHECK NOT NULL NOT VALID (for new and updated rows)
             # Only if you need NOT NULL:
             add_check_constraint :#{table_name}, "#{column_name} IS NOT NULL", name: "check_#{table_name}_#{column_name}_not_null", validate: false
          3. BACKFILL the column (using a job or something else, chucking by PK)
             # Your own script to backfill in batches
          4. VALIDATE CONSTRAINT (check whole table)
             # Only if you added the constraint in step 3:
             validate_check_constraint :#{table_name}, name: "check_#{table_name}_#{column_name}_not_null"
          5. ALTER COLUMN SET NOT NULL
             # Only if you need NOT NULL:
             change_column_null :#{table_name}, :#{column_name}, false
          6. DROP CONSTRAINT
             # Only if you added the constraint in step 3:
             remove_check_constraint :#{table_name}, name: "check_#{table_name}_#{column_name}_not_null"
        ERROR
      end
    end
  end
end
