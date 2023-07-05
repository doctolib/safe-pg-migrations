# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module TimeoutManagement
      def with_setting(key, value)
        old_value = query_value("SHOW #{key}")
        execute("SET #{key} TO #{quote(value)}")
        begin
          yield
        ensure
          begin
            execute("SET #{key} TO #{quote(old_value)}")
          rescue ActiveRecord::StatementInvalid => e
            # Swallow `PG::InFailedSqlTransaction` exceptions so as to keep the
            # original exception (if any).
            raise unless e.cause.is_a?(PG::InFailedSqlTransaction)
          end
        end
      end

      def without_statement_timeout(&block)
        with_setting(:statement_timeout, 0, &block)
      end

      def without_lock_timeout(&block)
        with_setting(:lock_timeout, 0, &block)
      end

      def without_timeout(&block)
        without_statement_timeout { without_lock_timeout(&block) }
      end
    end
  end
end
