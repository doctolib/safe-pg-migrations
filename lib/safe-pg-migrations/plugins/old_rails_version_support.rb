# frozen_string_literal: true

module SafePgMigrations
  module OldRailsVersionSupport
    ACTIVE_RECORD_VERSION = ActiveRecord::VERSION::STRING

    ruby2_keywords def validate_foreign_key(from_table, to_table = nil, **options)
      if ACTIVE_RECORD_VERSION < '6'
        super(from_table, to_table || options)
      else
        super(from_table, to_table, **options)
      end
    end

    ruby2_keywords def foreign_key_exists?(from_table, to_table = nil, **options)
      if ACTIVE_RECORD_VERSION < '6'
        super(from_table, to_table || options)
      else
        super(from_table, to_table, **options)
      end
    end
  end
end
