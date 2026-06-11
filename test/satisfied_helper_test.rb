# frozen_string_literal: true

require 'test_helper'

class SatisfiedHelperTest < Minitest::Test
  def test_supports_check_constraints
    SafePgMigrations::Helpers::SatisfiedHelper.stubs(:satisfies_add_check_constraints?).returns(true)
    SafePgMigrations::Helpers::SatisfiedHelper.satisfies_add_check_constraints!
  end

  def test_error_when_check_constraint_unsatisfied
    SafePgMigrations::Helpers::SatisfiedHelper.stubs(:satisfies_add_check_constraints?).returns(false)
    assert_raises NotImplementedError, 'add_check_constraint is not supported in your ActiveRecord version' do
      SafePgMigrations::Helpers::SatisfiedHelper.satisfies_add_check_constraints!
    end
  end

  def test_pg_version_unsatisfied_change_column_null_requirements
    SafePgMigrations::Helpers::SatisfiedHelper.stubs(:satisfies_add_check_constraints?).returns(true)
    SafePgMigrations.stubs(:pg_version_num).returns(110_000)
    refute_predicate SafePgMigrations::Helpers::SatisfiedHelper, :satisfies_change_column_null_requirements?
  end
end
