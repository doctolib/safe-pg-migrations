# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module BlockingActivitySelector
      FILTERED_COLUMNS = %w[
        blocked_activity.xact_start
        blocked_locks.locktype
        blocked_locks.mode
        blocking_activity.pid
        blocked_locks.transactionid
      ].freeze

      VERBOSE_COLUMNS = %w[
        blocking_activity.query
        blocked_activity.xact_start
      ].freeze

      def select_blocking_queries_sql
        columns =
          (
            if SafePgMigrations.config.blocking_activity_logger_verbose
              VERBOSE_COLUMNS
            else
              FILTERED_COLUMNS
            end
          )

        <<~SQL.squish
        SELECT #{columns.join(", ")}
        FROM pg_catalog.pg_locks           blocked_locks
        JOIN pg_catalog.pg_stat_activity   blocked_activity
          ON blocked_activity.pid = blocked_locks.pid
        JOIN pg_catalog.pg_locks           blocking_locks
          ON blocking_locks.locktype = blocked_locks.locktype
          AND blocking_locks.DATABASE      IS NOT DISTINCT FROM blocked_locks.DATABASE
          AND blocking_locks.relation      IS NOT DISTINCT FROM blocked_locks.relation
          AND blocking_locks.page          IS NOT DISTINCT FROM blocked_locks.page
          AND blocking_locks.tuple         IS NOT DISTINCT FROM blocked_locks.tuple
          AND blocking_locks.virtualxid    IS NOT DISTINCT FROM blocked_locks.virtualxid
          AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
          AND blocking_locks.classid       IS NOT DISTINCT FROM blocked_locks.classid
          AND blocking_locks.objid         IS NOT DISTINCT FROM blocked_locks.objid
          AND blocking_locks.objsubid      IS NOT DISTINCT FROM blocked_locks.objsubid
          AND blocking_locks.pid != blocked_locks.pid
        JOIN pg_catalog.pg_stat_activity   blocking_activity
          ON blocking_activity.pid = blocking_locks.pid
        WHERE blocked_locks.pid = %d
        SQL
      end
    end
  end
end
