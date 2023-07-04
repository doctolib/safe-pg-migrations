# frozen_string_literal: true

module SafePgMigrations
  module StrongMigrationsIntegration
    class << self
      def initialize
        return unless strong_migration_available?

        StrongMigrations.disable_check(:add_column_default)
        StrongMigrations.disable_check(:add_column_default_callable)
        StrongMigrations.add_check do |method, args|
          break unless method == :add_column

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

            check_message += <<~CHECK if SafePgMigrations.config.backfill_batch_size_limit

              Also, please note that SafePgMigrations is configured to raise if the table has more than
              #{SafePgMigrations.config.backfill_batch_size_limit} rows.
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
  end
end
