# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module AddCheckConstraintHelper

      class << self
        include SatisfiedHelper

        def support_add_check_constraints!
          return if satisfied? '>=6.1.0'

          raise NotImplementedError, 'add_check_constraint is not supported in your ActiveRecord version'
        end
      end
    end
  end
end
