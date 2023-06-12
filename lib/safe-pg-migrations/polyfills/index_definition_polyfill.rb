# frozen_string_literal: true

module SafePgMigrations
  module Polyfills
    module IndexDefinitionPolyfill
      include Helpers::SatisfiedHelper

      protected

      IndexDefinition = Struct.new(:table, :name)

      def index_definition(table_name, column_name, **options)
        return super(table_name, column_name, **options) if Helpers::SatisfiedHelper.satisfied? '>=6.1.0'

        index_name = options.key?(:name) ? options[:name].to_s : index_name(table_name, index_column_names(column_name))
        validate_index_length!(table_name, index_name, options.fetch(:internal, false))

        IndexDefinition.new(table_name, index_name)
      end
    end
  end
end
