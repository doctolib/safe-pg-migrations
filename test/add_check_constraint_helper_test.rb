# frozen_string_literal: true

require 'test_helper'

class AddCheckConstraintHelperTest < Minitest::Test
  def test_supports_check_constraints
    if Gem::Requirement.new('>6.1').satisfied_by?(Gem::Version.new(::ActiveRecord::VERSION::STRING))
      SafePgMigrations::Helpers::AddCheckConstraintHelper.support_add_check_constraints!
    else
      assert_raises NotImplementedError, 'add_check_constraint is not supported in your ActiveRecord version' do
        SafePgMigrations::Helpers::AddCheckConstraintHelper.support_add_check_constraints!
      end
    end
  end
end
