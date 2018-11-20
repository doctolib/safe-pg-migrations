# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'bundler/setup'

require 'minitest/autorun'
require 'mocha/setup'
require 'active_record'
require 'active_support'
require 'pry'

require 'safe-pg-migrations/base'

ENV['DATABASE_URL'] ||= 'postgres://postgres@localhost/safe_pg_migrations_test'

ActiveRecord::Base.logger = ActiveSupport::Logger.new('debug.log', 0, 100 * 1024 * 1024)
ActiveRecord::Base.establish_connection
ActiveRecord::InternalMetadata.create_table

ActiveRecord::Migration.prepend(SafePgMigrations::Migration)

class Minitest::Test
  make_my_diffs_pretty!
end
