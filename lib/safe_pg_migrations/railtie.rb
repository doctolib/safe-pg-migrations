# frozen_string_literal: true

require 'safe_pg_migrations/base'

module SafePgMigrations
  class Railtie < Rails::Railtie
    initializer 'sage_pg_migrations.insert_into_active_record' do
      ActiveSupport.on_load :active_record do
        ActiveRecord::Migration.prepend(SafePgMigrations::Migration)
      end
    end
  end
end
