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

          # Block volatile defaults with backfill
          if default_value_backfill == :update_in_batches && volatile_default?(default)
            default_display = default.is_a?(Proc) ? '<Proc>' : default

            check_message = <<~CHECK
              Using default_value_backfill: :update_in_batches with volatile default '#{default_display}' is not allowed.

              Volatile defaults (like NOW(), clock_timestamp(), random()) are evaluated per row and can cause
              migrations to hang for a very long time on large tables.

              Please backfill volatile defaults manually instead. See the safe-pg-migrations README for the
              recommended approach.
            CHECK

            stop! check_message
          end
        end
      end

      private

      def strong_migration_available?
        Object.const_defined? :StrongMigrations
      end

      def volatile_default?(default)
        return false if default.nil?

        # Proc/lambda → volatile
        return true if default.is_a?(Proc)

        # String defaults only
        return false unless default.is_a?(String)

        # Check against known volatile patterns
        volatile_patterns = [
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
        ]

        volatile_patterns.any? { |pattern| default.match?(pattern) }
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
    end

    def add_column(table_name, *args, **options)
      return super unless respond_to?(:safety_assured)

      default_value_backfill = options.fetch(:default_value_backfill, :auto)

      # Auto backfill (non-volatile) is safe - use safety_assured
      return safety_assured { super } if default_value_backfill == :auto

      # Non-volatile defaults with backfill are also safe - use safety_assured
      default = options[:default]
      return safety_assured { super } if default_value_backfill == :update_in_batches && !volatile_default?(default)

      # Volatile defaults with backfill - don't auto-approve, let the check above catch it
      super
    end

    private

    def volatile_default?(default)
      return false if default.nil?

      # Proc/lambda → volatile
      return true if default.is_a?(Proc)

      # String defaults only
      return false unless default.is_a?(String)

      # Check against known volatile patterns
      volatile_patterns = [
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
      ]

      volatile_patterns.any? { |pattern| default.match?(pattern) }
    end
  end
end
