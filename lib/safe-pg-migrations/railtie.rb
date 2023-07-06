# frozen_string_literal: true

require 'safe-pg-migrations/base'

module SafePgMigrations
  class Railtie < Rails::Railtie
    initializer 'safe_pg_migrations.insert_into_active_record' do
      ActiveSupport.on_load :active_record do
        ActiveRecord::Migration.prepend(SafePgMigrations::Migration)
        ActiveRecord::Migration.singleton_class.prepend(SafePgMigrations::Migration::ClassMethods)
      end

      SafePgMigrations::StrongMigrationsIntegration.initialize
    end
  end
end
