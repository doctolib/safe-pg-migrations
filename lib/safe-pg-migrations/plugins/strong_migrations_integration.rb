# frozen_string_literal: true

module SafePgMigrations
  module StrongMigrationsIntegration
    class << self
      def initialize
        return unless strong_migration_available?

        StrongMigrations.disable_check(:add_column_default)
        StrongMigrations.disable_check(:add_column_default_callable)
        StrongMigrations.add_check do |method, args|
          next unless method == :add_column

          options = args.last.is_a?(Hash) ? args.last : {}

          default_value_backfill = options.fetch(:default_value_backfill, :auto)

          if default_value_backfill == :update_in_batches
            check_message = <<~CHECK
              default_value_backfill: :update_in_batches will take time if the table is too big.

              Your configuration sets a pause of #{SafePgMigrations.config.backfill_pause} seconds between batches of
              #{SafePgMigrations.config.backfill_batch_size} rows. Each batch execution will take time as well. Please
              check that the estimated duration of the migration is acceptable
              before adding `safety_assured`.
            CHECK

            check_message += <<~CHECK if SafePgMigrations.config.default_value_backfill_threshold

              Also, please note that SafePgMigrations is configured to raise if the table has more than
              #{SafePgMigrations.config.default_value_backfill_threshold} rows.
            CHECK

            stop! check_message
          end
        end
      end

      private

      def strong_migration_available?
        Object.const_defined? :StrongMigrations
      end
    end

    SAFE_METHODS = %i[
      execute
      add_index
      add_reference
      add_belongs_to
      change_column_null
      add_foreign_key
      add_check_constraint
    ].freeze

    SAFE_METHODS.each do |method|
      define_method method do |*args, **options|
        return super(*args, **options) unless respond_to?(:safety_assured)

        safety_assured { super(*args, **options) }
      end
      method
    end

    ruby2_keywords def add_column(table_name, *args)
      return super(table_name, *args) unless respond_to?(:safety_assured)

      options = args.last.is_a?(Hash) ? args.last : {}

      return safety_assured { super(table_name, *args) } if options.fetch(:default_value_backfill, :auto) == :auto

      super(table_name, *args)
    end
  end
end
