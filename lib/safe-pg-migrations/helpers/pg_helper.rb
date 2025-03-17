# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module PgHelper
      def pg_duration(duration)
        value, unit = duration.integer? ? [duration, 's'] : [(duration * 1000).to_i, 'ms']
        "#{value}#{unit}"
      end
    end
  end
end
