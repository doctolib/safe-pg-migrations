# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer
    module RemoveColumnIndex
      def remove_column_with_composite_index(table, column)
        existing_indexes = indexes(table).select { |index|
          index.columns.size > 1 && index.columns.include?(column.to_s)
        }

        return unless existing_indexes.any?

        error_message = <<~ERROR
          Cannot drop column #{column} from table #{table} because composite index(es): #{existing_indexes.map(&:name).join(', ')} is/are present.
          If they are still required, create the index(es) without #{column} before dropping the existing index(es).
          Then you will be able to drop the column.
        ERROR

        raise StandardError, error_message
      end
    end
  end
end
