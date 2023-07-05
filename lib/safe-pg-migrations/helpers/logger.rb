# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module Logger
      class << self
        def say(message, sub_item: false, sensitive: false, warn_sensitive_logs: true)
          return unless SafePgMigrations.current_migration

          if sensitive
            log_sensitive message, sub_item: sub_item
            if warn_sensitive_logs && sensitive_logger?
              log 'Sensitive data sent to sensitive logger', sub_item: sub_item
            end
          else
            log message, sub_item: sub_item
          end
        end

        def say_method_call(method, *args, sensitive: false, warn_sensitive_logs: true, **options)
          args += [options] unless options.empty?

          say "#{method}(#{args.map(&:inspect) * ', '})",
              sub_item: true, sensitive: sensitive, warn_sensitive_logs: warn_sensitive_logs
        end

        private

        def log(message, sub_item:)
          SafePgMigrations.current_migration.say message, sub_item
        end

        def log_sensitive(message, sub_item:)
          if sensitive_logger?
            SafePgMigrations.config.sensitive_logger.info message
          else
            log message, sub_item: sub_item
          end
        end

        def sensitive_logger?
          SafePgMigrations.config.sensitive_logger
        end
      end
    end
  end
end
