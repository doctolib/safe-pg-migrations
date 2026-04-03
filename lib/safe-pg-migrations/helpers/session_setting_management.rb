# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module SessionSettingManagement
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

      def without_statement_timeout(&)
        with_setting(:statement_timeout, 0, &)
      end

      def without_lock_timeout(&)
        with_setting(:lock_timeout, 0, &)
      end

      def without_timeout(&)
        without_statement_timeout { without_lock_timeout(&) }
      end
    end
  end
end
