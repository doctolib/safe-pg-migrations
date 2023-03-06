# frozen_string_literal: true

module SafePgMigrations
  module Polyfills
    module VerboseQueryLogsPolyfill
      class << self
        include SatisfiedHelper

        def verbose_query_logs
          return ActiveRecord.verbose_query_logs if satisfied? '>=6.1.0'

          ActiveRecord::Base.verbose_query_logs
        end

        def verbose_query_logs=(value)
          if satisfied? '>=6.1.0'
            ActiveRecord.verbose_query_logs = value
            return
          end

          ActiveRecord::Base.verbose_query_logs = value
        end
      end
    end
  end
end
