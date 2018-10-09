# frozen_string_literal: true

module SafePgMigrations
  module BlockingActivityLogger
    SELECT_BLOCKING_QUERIES_SQL = <<~SQL.squish
      SELECT blocking_activity.query
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

    %i[
      add_column remove_column add_foreign_key remove_foreign_key change_column_default
      change_column_null create_table add_index remove_index
    ].each do |method|
      define_method method do |*args, &block|
        log_blocking_queries { super(*args, &block) }
      end
    end

    private

    def log_blocking_queries
      blocking_queries_retriever_thread =
        Thread.new do
          sleep SafePgMigrations.config.blocking_activity_logger_delay
          SafePgMigrations.alternate_connection.query_values(SELECT_BLOCKING_QUERIES_SQL % raw_connection.backend_pid)
        end

      yield

      blocking_queries_retriever_thread.kill
    rescue ActiveRecord::LockWaitTimeout
      SafePgMigrations.say 'Lock timeout.', true
      queries =
        begin
          blocking_queries_retriever_thread.value
        rescue StandardError => e
          SafePgMigrations.say("Error while retrieving blocking queries: #{e}", true)
          nil
        end

      raise if queries.nil?

      if queries.empty?
        SafePgMigrations.say 'Could not find any blocking query.', true
      else
        SafePgMigrations.say(
          "Statement was being blocked by the following #{'query'.pluralize(queries.size)}:", true
        )
        SafePgMigrations.say '', true
        queries.each { |query| SafePgMigrations.say "  #{query}", true }
        SafePgMigrations.say '', true
      end

      raise
    end
  end
end
