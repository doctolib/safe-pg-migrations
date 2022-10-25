# frozen_string_literal: true

require 'active_support/core_ext/numeric/time'

module SafePgMigrations
  class Configuration
    attr_accessor :safe_timeout, :blocking_activity_logger_margin, :blocking_activity_logger_verbose, :batch_size,
                  :retry_delay, :max_tries

    def initialize
      self.safe_timeout = 5.seconds
      self.blocking_activity_logger_margin = 1.second
      self.blocking_activity_logger_verbose = true
      self.batch_size = 1000
      self.retry_delay = 1.minute
      self.max_tries = 5
    end

    def pg_safe_timeout
      pg_duration(safe_timeout)
    end

    def pg_duration(duration)
      value, unit = duration.integer? ? [duration, 's'] : [(duration * 1000).to_i, 'ms']
      "#{value}#{unit}"
    end
  end
end
