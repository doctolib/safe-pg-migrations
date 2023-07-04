# frozen_string_literal: true

require 'safe-pg-migrations/base'

module SafePgMigrations
  class Railtie < Rails::Railtie
    initializer 'safe_pg_migrations.insert_into_active_record' do
      ActiveSupport.on_load :active_record do
        ActiveRecord::Migration.prepend(SafePgMigrations::Migration)
        ActiveRecord::Migration.singleton_class.prepend(SafePgMigrations::Migration::ClassMethods)
      end

      break unless Object.const_defined? :StrongMigrations

      StrongMigrations.add_check do |method, args|
        break unless method == :add_column

        options = args.last.is_a?(Hash) ? args.last : {}

        default_value_backfill = options.fetch(:default_value_backfill, :auto)

        if default_value_backfill == :update_in_batches
          check_message = <<~CHECK
            default_value_backfill: :update_in_batches will take time if the table is too big.

            Your configuration sets a pause of #{SafePgMigrations.config.backfill_pause} seconds between batches of
            #{SafePgMigrations.config.backfill_batch_size} rows. Each batch execution will take time as well. Please
            check that the estimated duration of the migration is acceptable before adding `safety_assured`.
          CHECK

          check_message += <<~CHECK if SafePgMigrations.config.backfill_batch_size_limit

            Also, please note that SafePgMigrations is configured to raise if the table has more than
            #{SafePgMigrations.config.backfill_batch_size_limit} rows.
          CHECK

          stop! check_message
        end
      end
    end
  end
end
