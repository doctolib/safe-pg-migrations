# frozen_string_literal: true

module SafePgMigrations
  module LegacyActiveRecordSupport
    ruby2_keywords def validate_foreign_key(*args)
      return super(*args) if satisfied? '>=6.0.0'

      from_table, to_table, options = args
      super(from_table, to_table || options)
    end

    ruby2_keywords def foreign_key_exists?(*args)
      return super(*args) if satisfied? '>=6.0.0'

      from_table, to_table, options = args
      super(from_table, to_table || options)
    end

    ruby2_keywords def remove_foreign_key(*args)
      return super(*args) if satisfied? '>=6.0.0'

      from_table = args[0]
      to_table = args[1].is_a?(String) ? args[1] : nil
      options ||= args.last.is_a?(Hash) ? args.last : {}
      to_table ||= options[:to_table]
      options.delete(:to_table)
      super(from_table, to_table || options)
    end

    private

    def satisfied?(version)
      Gem::Requirement.new(version).satisfied_by? Gem::Version.new(::ActiveRecord::VERSION::STRING)
    end
  end
end
