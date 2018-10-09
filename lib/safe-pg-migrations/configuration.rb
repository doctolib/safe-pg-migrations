# frozen_string_literal: true

require 'active_support/core_ext/numeric/time'

module SafePgMigrations
  class Configuration
    attr_accessor :safe_timeout
    attr_accessor :blocking_activity_logger_delay # Must be close to but smaller than safe_timeout.
    attr_accessor :batch_size
    attr_accessor :retry_delay
    attr_accessor :max_tries

    def initialize
      self.safe_timeout = '5s'
      self.blocking_activity_logger_delay = 4.seconds
      self.batch_size = 1000
      self.retry_delay = 2.minutes
      self.max_tries = 5
    end
  end
end
