# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module Logger
      class << self
        def say(message, sub_item: false)
          return unless SafePgMigrations.current_migration

          log message, sub_item: sub_item
        end

        def say_method_call(method, *args, **options)
          args += [options] unless options.empty?

          say "#{method}(#{args.map(&:inspect) * ', '})", sub_item: true
        end

        private

        def log(message, sub_item:)
          SafePgMigrations.current_migration.say message, sub_item
        end
      end
    end
  end
end
