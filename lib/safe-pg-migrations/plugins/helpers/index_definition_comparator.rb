# frozen_string_literal: true

module SafePgMigrations::Helpers
  class IndexDefinitionComparator
    def initialize(index_definition_a, index_definition_b)
      @index_definition_a = index_definition_a
      @index_definition_b = index_definition_b
    end

    def equal?
      return false unless %i[table name type comment lengths orders opclasses].all? do |attribute|
        options_equal? @index_definition_a.public_send(attribute), @index_definition_b.public_send(attribute)
      end

      wheres_equal? && columns_equal? && uniques_equal? && usings_equal?
    end

    private

    def usings_equal?
      options_equal?(@index_definition_a.using || 'btree', @index_definition_b.using || 'btree')
    end

    def uniques_equal?
      @index_definition_a.unique.presence == @index_definition_b.unique.presence
    end

    def columns_equal?
      @index_definition_a.columns.map(&:to_s).sort == @index_definition_b.columns.map(&:to_s).sort
    end

    def wheres_equal?
      normalize_where = lambda do |where|
        where
          .to_s
          .gsub(/\s+/, ' ') # replacing any duplicated space with one
          .gsub(/^\s*\((.*)\)\s*$/, '\1') # removing trailing ()
          .strip
      end

      where_a = normalize_where.call(@index_definition_a.where)
      where_b = normalize_where.call(@index_definition_b.where)

      options_equal?(where_a, where_b)
    end

    def options_equal?(option_a, option_b)
      if option_a.is_a? Hash
        return false unless option_b.is_a? Hash
        return false unless option_a.symbolize_keys.keys.sort == option_b.symbolize_keys.keys.sort

        option_a.keys.all? do |key|
          strings_equal? option_a.with_indifferent_access[key], option_b.with_indifferent_access[key]
        end
      else
        !option_b.is_a?(Hash) && strings_equal?(option_a, option_b)
      end
    end

    def strings_equal?(string_or_sym_a, string_or_sym_b)
      string_or_sym_a.to_s == string_or_sym_b.to_s
    end
  end
end
