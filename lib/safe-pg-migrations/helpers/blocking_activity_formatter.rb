# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module BlockingActivityFormatter
      def log_queries(queries)
        if queries.empty?
          SafePgMigrations.say "Could not find any blocking query.", true
        else
          SafePgMigrations.say(
            "Statement was being blocked by the following #{"query".pluralize(queries.size)}:",
            true
          )
          SafePgMigrations.say "", true
          output_blocking_queries(queries)
          SafePgMigrations.say(
            "Beware, some of those queries might run in a transaction. In this case the locking query might be " \
              "located elsewhere in the transaction",
            true
          )
          SafePgMigrations.say "", true
        end
      end

      private

      def output_blocking_queries(queries)
        if SafePgMigrations.config.blocking_activity_logger_verbose
          queries.each do |query, start_time|
            SafePgMigrations.say "#{format_start_time start_time}:  #{query}",
                                 true
          end
        else
          output_confidentially_blocking_queries(queries)
        end
      end

      def output_confidentially_blocking_queries(queries)
        queries.each do |start_time, locktype, mode, pid, transactionid|
          SafePgMigrations.say(
            "#{format_start_time(start_time)}: lock type: #{locktype || "null"}, " \
              "lock mode: #{mode || "null"}, " \
              "lock pid: #{pid || "null"}, " \
              "lock transactionid: #{transactionid || "null"}",
            true
          )
        end
      end

      def format_start_time(start_time, reference_time = Time.now)
        start_time = Time.parse(start_time) unless start_time.is_a? Time
        duration = (reference_time - start_time).round
        "transaction started #{duration} #{"second".pluralize(duration)} ago"
      end
    end
  end
end
