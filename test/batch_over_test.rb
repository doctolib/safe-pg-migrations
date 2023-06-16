# frozen_string_literal: true

require 'test_helper'

class BlockingActivityLoggerTest < Minitest::Test
  def test_can_batch_over_numeric_ids
    @connection.create_table(:users)
    20.times { @connection.execute('INSERT INTO users (id) VALUES (default);') }
    yields = []

    SafePgMigrations::Helpers::BatchOver.new(model, of: 10).in_batches do |rel|
      assert_equal 10, rel.count
      yields << rel
    end

    assert_equal 2, yields.count
  end

  def test_can_batch_over_uuids
    @connection.enable_extension 'pgcrypto' unless @connection.extension_enabled?('pgcrypto')
    @connection.create_table(:users, id: :uuid, force: true)

    20.times { @connection.execute('INSERT INTO users (id) VALUES (default);') }
    yields = []

    SafePgMigrations::Helpers::BatchOver.new(model, of: 10).in_batches do |rel|
      assert_equal 10, rel.count
      yields << rel
    end

    assert_equal 2, yields.count
  end

  def test_when_batch_has_exactly_one_element
    @connection.create_table(:users)
    @connection.execute('INSERT INTO users (id) VALUES (default);')

    yields = []

    SafePgMigrations::Helpers::BatchOver.new(model, of: 10).in_batches do |rel|
      assert_equal 1, rel.count
      yields << rel
    end

    assert_equal 1, yields.count
  end

  def test_when_batch_has_no_elements
    @connection.create_table(:users)

    SafePgMigrations::Helpers::BatchOver.new(model, of: 10).in_batches do
      flunk 'Should not yield because no element'
    end
  end

  def test_should_use_comparison_and_not_id_list
    @connection.create_table(:users)
    20.times { @connection.execute('INSERT INTO users (id) VALUES (default);') }

    relations = []
    SafePgMigrations::Helpers::BatchOver.new(model, of: 10).in_batches do |rel|
      relations << rel
      assert_equal 10, rel.count
    end

    assert_equal 2, relations.count

    assert_equal(
      'SELECT "users".* FROM "users" WHERE "users"."id" >= $1 AND "users"."id" < $2 ORDER BY "users"."id" ASC',
      relations.first.arel.to_sql
    )

    assert_equal(
      'SELECT "users".* FROM "users" WHERE "users"."id" >= $1 ORDER BY "users"."id" ASC',
      relations.second.arel.to_sql
    )
  end

  private

  def model
    Class.new(ActiveRecord::Base) { self.table_name = 'users' }
  end
end
