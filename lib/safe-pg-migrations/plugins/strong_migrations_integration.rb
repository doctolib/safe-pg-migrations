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
          default = options[:default]
          default_value_backfill = options.fetch(:default_value_backfill, :auto)

          next unless default_value_backfill == :update_in_batches

          stop! backfill_check_message(default)
        end
      end

      def volatile_default?(default)
        return false if default.nil?
        return true if default.is_a?(Proc)
        return false unless default.is_a?(String)

        VOLATILE_PATTERNS.any? { |pattern| default.match?(pattern) }
      end

      private

      def strong_migration_available?
        Object.const_defined? :StrongMigrations
      end

      def backfill_check_message(default)
        if volatile_default?(default)
          default_display = default.is_a?(Proc) ? '<Proc>' : default

          <<~CHECK
            Using default_value_backfill: :update_in_batches with volatile default '#{default_display}' is not allowed.

            Volatile defaults (like NOW(), clock_timestamp(), random()) are evaluated per row and can cause
            migrations to hang for a very long time on large tables.

            Please backfill volatile defaults manually instead. See the safe-pg-migrations README for the
            recommended approach.
          CHECK
        else
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

          check_message
        end
      end
    end

    VOLATILE_PATTERNS = [
      /\bclock_timestamp\s*\(/i,
      /\bnow\s*\(/i,
      /\bcurrent_timestamp\b/i,
      /\bcurrent_time\b/i,
      /\bcurrent_date\b/i,
      /\brandom\s*\(/i,
      /\buuid_generate/i,
      /\bgen_random_uuid\s*\(/i,
      /\btimeofday\s*\(/i,
      /\btransaction_timestamp\s*\(/i,
      /\bstatement_timestamp\s*\(/i,
    ].freeze

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
    end

    def add_column(table_name, *args, **options)
      return super unless respond_to?(:safety_assured)

      default_value_backfill = options.fetch(:default_value_backfill, :auto)

      # Auto backfill is safe - use safety_assured
      return safety_assured { super } if default_value_backfill == :auto

      # :update_in_batches always requires explicit safety_assured (volatile defaults will be
      # blocked by the check above before reaching this point)
      super
    end

    private

    def volatile_default?(default)
      StrongMigrationsIntegration.volatile_default?(default)
    end
  end
end
