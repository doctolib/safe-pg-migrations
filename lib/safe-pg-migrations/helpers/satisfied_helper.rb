# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module SatisfiedHelper
      class << self
        def satisfies_change_column_null_requirements?
          satisfies_add_check_constraints? && SafePgMigrations.pg_version_num >= 120_000
        end

        def satisfies_add_check_constraints!
          return if satisfies_add_check_constraints?

          raise NotImplementedError, 'add_check_constraint is not supported in your ActiveRecord version'
        end

        def satisfies_add_check_constraints?
          satisfied? '>=6.1.0'
        end

        def satisfied?(version)
          Gem::Requirement.new(version).satisfied_by? Gem::Version.new(::ActiveRecord::VERSION::STRING)
        end
      end
    end
  end
end
