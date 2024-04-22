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
                    max_tries
                    retry_delay
                    sensitive_logger
                    increase_lock_timeout_on_retry
                  ])
    attr_reader :lock_timeout, :safe_timeout, :max_lock_timeout_for_retry

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
      self.max_lock_timeout_for_retry = 1.second
      self.sensitive_logger = nil
      self.increase_lock_timeout_on_retry = false
    end

    def lock_timeout=(value)
      raise 'Setting lock timeout to 0 disables the lock timeout and is dangerous' if value == 0.seconds

      unless value.nil? || (value < safe_timeout && value <= max_lock_timeout_for_retry)
        raise ArgumentError, "Lock timeout (#{value}) cannot be greater than the safe timeout (#{safe_timeout}) or the max lock timeout for retry (#{max_lock_timeout_for_retry})"
      end

      @lock_timeout = value
    end

    def safe_timeout=(value)
      raise 'Setting safe timeout to 0 or nil disables the safe timeout and is dangerous' unless value && value > 0.seconds

      unless lock_timeout.nil? || (value > lock_timeout && value >= max_lock_timeout_for_retry)
        raise ArgumentError, "Safe timeout (#{value}) cannot be lower than the lock timeout (#{lock_timeout}) or the max lock timeout for retry (#{max_lock_timeout_for_retry})"
      end

      @safe_timeout = value
    end

    def max_lock_timeout_for_retry=(value)
      unless lock_timeout.nil? || (value >= lock_timeout && value <= safe_timeout)
        raise ArgumentError, "Max lock timeout for retry (#{value}) cannot be lower than the lock timeout (#{lock_timeout}) and greater than the safe timeout (#{safe_timeout})"
      end

      @max_lock_timeout_for_retry = value
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
