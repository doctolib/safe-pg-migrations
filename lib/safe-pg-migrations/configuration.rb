# frozen_string_literal: true

require 'active_support/core_ext/numeric/time'

module SafePgMigrations
  class Configuration
    attr_accessor :safe_timeout, :blocking_activity_logger_margin, :blocking_activity_logger_verbose,
                  :backfill_batch_size, :backfill_pause, :retry_delay, :max_tries

    def initialize
      self.safe_timeout = 5.seconds
      self.blocking_activity_logger_margin = 1.second
      self.blocking_activity_logger_verbose = true
      self.backfill_batch_size = 100_000
      self.backfill_pause = 0.5.second
      self.retry_delay = 1.minute
      self.max_tries = 5
    end

    def pg_statement_timeout
      pg_duration safe_timeout
    end

    def pg_lock_timeout
      # if statement timeout and lock timeout have the same value, statement timeout will raise in priority. We actually
      # need the opposite for BlockingActivityLogger to detect lock timeouts correctly.
      # By reducing the lock timeout by a very small margin, we ensure that the lock timeout is raised in priority
      pg_duration safe_timeout * 0.99
    end

    private

    def pg_duration(duration)
      value, unit = duration.integer? ? [duration, 's'] : [(duration * 1000).to_i, 'ms']
      "#{value}#{unit}"
    end
  end
end
