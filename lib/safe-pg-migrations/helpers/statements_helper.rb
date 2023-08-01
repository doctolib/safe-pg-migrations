# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module StatementsHelper
      RETRIABLE_SCHEMA_STATEMENTS = %i[
        add_check_constraint
        add_column
        add_foreign_key
        change_column_default
        change_column_null
        create_table
        remove_column
        remove_foreign_key
        drop_table
      ].freeze
    end
  end
end
