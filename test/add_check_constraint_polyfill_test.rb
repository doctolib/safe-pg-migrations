# frozen_string_literal: true

require 'test_helper'

class BlockingActivityLoggerTest < Minitest::Test
  class DummyTester
    def supports_check_constraints?
      true
    end
  end

  def test_supports_check_constraints
    tester = Class.new(DummyTester) do
      include SafePgMigrations::Polyfills::AddCheckConstraintPolyfill
    end.new

    if Gem::Requirement.new('>6.1').satisfied_by?(Gem::Version.new(::ActiveRecord::VERSION::STRING))
      assert_predicate tester, :supports_check_constraints?
    else
      assert_raises NotImplementedError, 'add_check_constraint is not supported in your ActiveRecord version' do
        tester.supports_check_constraints?
      end
    end
  end
end
