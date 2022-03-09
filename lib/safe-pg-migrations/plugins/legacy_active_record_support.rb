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

    protected

    IndexDefinition = Struct.new(:table, :name)

    def index_definition(table_name, column_name, **options)
      return super(table_name, column_name, **options) if satisfied? '>=6.1.0'

      index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, index_column_names(column_name))
      validate_index_length!(table_name, index_name, options.fetch(:internal, false))

      IndexDefinition.new(table_name, index_name)
    end

    private

    def satisfied?(version)
      Gem::Requirement.new(version).satisfied_by? Gem::Version.new(::ActiveRecord::VERSION::STRING)
    end
  end
end
