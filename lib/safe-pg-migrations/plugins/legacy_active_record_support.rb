# frozen_string_literal: true

module SafePgMigrations
  module LegacyActiveRecordSupport
    ruby2_keywords def validate_foreign_key(from_table, to_table = nil, *options)
      return super(from_table, to_table || options) unless satisfied? '>=6.0.0'

      super(from_table, to_table, *options)
    end

    ruby2_keywords def foreign_key_exists?(from_table, to_table = nil, *options)
      return super(from_table, to_table || options) unless satisfied? '>=6.0.0'

      super(from_table, to_table, *options)
    end

    private

    def satisfied?(version)
      Gem::Requirement.new(version).satisfied_by? Gem::Version.new(::ActiveRecord::VERSION::STRING)
    end
  end
end
