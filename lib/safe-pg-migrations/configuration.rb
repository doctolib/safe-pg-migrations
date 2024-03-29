# frozen_string_literal: true

require 'active_support/core_ext/numeric/time'

module SafePgMigrations
  class Configuration
    attr_accessor(*%i[
                    backfill_batch_size
                    backfill_pause
                    blocking_activity_logger_margin
                    blocking_activity_logger_verbose
                    default_value_backfill_threshold
                    lock_timeout
                    max_tries
                    max_lock_timeout
                    retry_delay
                    sensitive_logger
                  ])
    attr_reader :safe_timeout

    def initialize
      self.default_value_backfill_threshold = nil
      self.safe_timeout = 5.seconds
      self.lock_timeout = nil
      self.blocking_activity_logger_margin = 1.second
      self.blocking_activity_logger_verbose = true
      self.backfill_batch_size = 100_000
      self.backfill_pause = 0.5.second
      self.retry_delay = 1.minute
      self.max_tries = 5
      self.max_lock_timeout = 1.second
      self.sensitive_logger = nil
    end

    def lock_timeout=(value)
      raise 'Setting lock timeout to 0 disables the lock timeout and is dangerous' if value == 0.seconds

      unless value.nil? || value < safe_timeout
        raise ArgumentError, "Lock timeout (#{value}) cannot be greater than safe timeout (#{safe_timeout})"
      end

      @lock_timeout = value
    end

    def safe_timeout=(value)
      raise 'Setting safe timeout to 0 disables the safe timeout and is dangerous' unless value

      unless lock_timeout.nil? || value > lock_timeout || value > max_lock_timeout
        raise ArgumentError, "Safe timeout (#{value}) cannot be less than lock timeout (#{lock_timeout})"
      end

      @safe_timeout = value
    end

    def pg_statement_timeout
      pg_duration safe_timeout
    end

    def pg_lock_timeout
      return pg_duration lock_timeout if lock_timeout

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
