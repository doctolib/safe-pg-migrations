# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module BlockingActivityFormatter
      def log_queries(queries)
        if queries.empty?
          SafePgMigrations::Helpers::Logger.say 'Could not find any blocking query.', sub_item: true
        else
          SafePgMigrations::Helpers::Logger.say <<~MESSAGE.rstrip, sub_item: true
            Statement was being blocked by the following #{'query'.pluralize(queries.size)}:
          MESSAGE

          SafePgMigrations::Helpers::Logger.say '', sub_item: true
          output_blocking_queries(queries)
          SafePgMigrations::Helpers::Logger.say <<~MESSAGE, sub_item: true
            Beware, some of those queries might run in a transaction. In this case the locking query might be located
            elsewhere in the transaction
          MESSAGE

          SafePgMigrations::Helpers::Logger.say '', sub_item: true
        end
      end

      private

      def output_blocking_queries(queries)
        if SafePgMigrations.config.blocking_activity_logger_verbose
          queries.each do |pid, query, start_time|
            SafePgMigrations::Helpers::Logger.say(
              "Query with pid #{pid || 'null'} started #{format_start_time start_time}: #{query}",
              sub_item: true
            )
          end
        else
          output_confidentially_blocking_queries(queries)
        end
      end

      def output_confidentially_blocking_queries(queries)
        queries.each do |start_time, locktype, mode, pid, transactionid|
          SafePgMigrations::Helpers::Logger.say(
            "Query with pid #{pid || 'null'} " \
            "started #{format_start_time(start_time)}: " \
            "lock type: #{locktype || 'null'}, " \
            "lock mode: #{mode || 'null'}, " \
            "lock transactionid: #{transactionid || 'null'}",
            sub_item: true
          )
        end
      end

      def format_start_time(start_time, reference_time = Time.now)
        start_time = Time.parse(start_time) unless start_time.is_a? Time

        duration = (reference_time - start_time).round
        "#{duration} #{'second'.pluralize(duration)} ago"
      end
    end
  end
end
