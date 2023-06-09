# frozen_string_literal: true

module SafePgMigrations
  module Polyfills
    module AddCheckConstraintPolyfill
      include SatisfiedHelper

      def supports_check_constraints?
        return super if satisfied? '>=6.1.0'

        raise NotImplementedError, 'add_check_constraint is not supported in your ActiveRecord version'
      end
    end
  end
end
