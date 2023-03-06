# frozen_string_literal: true

module SafePgMigrations
  module Polyfills
    module SatisfiedHelper
      private

      def satisfied?(version)
        Gem::Requirement.new(version).satisfied_by? Gem::Version.new(::ActiveRecord::VERSION::STRING)
      end
    end
  end
end
