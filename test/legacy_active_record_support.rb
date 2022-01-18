# frozen_string_literal: true

require 'test_helper'

class LegacyActiveRecordSupport < Minitest::Test
  def test_add_foreign_key_with_validation
    @connection.create_table(:users) { |t| t.string :email }
    @connection.create_table(:messages) do |t|
      t.string :message
      t.bigint :user_id
    end

    @migration =
      Class.new(ActiveRecord::Migration::Current) do
        def change
          add_foreign_key :messages, :users, validate: true
        end
      end.new

    calls = record_calls(@connection, :execute) { run_migration }
    assert_calls [
      "SET statement_timeout TO '5s'",
      'ALTER TABLE "messages" ADD CONSTRAINT "fk_rails_273a25a7a6" FOREIGN KEY ("user_id") REFERENCES "users" ("id")',
      "SET statement_timeout TO '70s'",
    ], calls
  end
end
