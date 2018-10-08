# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer
    %i[change_column_null add_foreign_key create_table].each do |method|
      define_method method do |*args, &block|
        with_setting(:statement_timeout, SAFE_TIMEOUT) { super(*args, &block) }
      end
    end

    def add_column(table_name, column_name, type, **options)
      default = options.delete(:default)
      null = options.delete(:null)

      if !default.nil? || null == false
        SafePgMigrations.say_method_call(:add_column, table_name, column_name, type, **options)
      end

      super

      unless default.nil?
        SafePgMigrations.say_method_call(:change_column_default, table_name, column_name, default)
        change_column_default(table_name, column_name, default)

        SafePgMigrations.say_method_call(:backfill_column_default, table_name, column_name)
        backfill_column_default(table_name, column_name)
      end

      if null == false # rubocop:disable Style/GuardClause
        SafePgMigrations.say_method_call(:change_column_null, table_name, column_name, null)
        change_column_null(table_name, column_name, null)
      end
    end

    def add_index(table_name, column_name, **options)
      if SAFE_MODE
        options[:algorithm] = :concurrently
        SafePgMigrations.say_method_call(:add_index, table_name, column_name, **options)
      end
      without_statement_timeout { super }
    end

    def remove_index(table_name, options = {})
      options = { column: options } unless options.is_a?(Hash)
      if SAFE_MODE
        options[:algorithm] = :concurrently
        SafePgMigrations.say_method_call(:remove_index, table_name, **options)
      end
      without_statement_timeout { super }
    end

    def backfill_column_default(table_name, column_name)
      quoted_table_name = quote_table_name(table_name)
      quoted_column_name = quote_column_name(column_name)
      primary_key_offset = 0
      loop do
        ids = query_values <<~SQL.squish
          SELECT id FROM #{quoted_table_name} WHERE id > #{primary_key_offset}
          ORDER BY id LIMIT #{BATCH_SIZE}
        SQL
        break if ids.empty?

        primary_key_offset = ids.last
        execute <<~SQL.squish
          UPDATE #{quoted_table_name} SET #{quoted_column_name} = DEFAULT WHERE id IN (#{ids.join(',')})
        SQL
      end
    end

    def with_setting(key, value)
      old_value = query_value("SHOW #{key}")
      execute("SET #{key} TO #{quote(value)}")
      begin
        yield
      ensure
        begin
          execute("SET #{key} TO #{quote(old_value)}")
        rescue ActiveRecord::StatementInvalid => e
          # Swallow `PG::InFailedSqlTransaction` exceptions so as to keep the
          # original exception (if any).
          raise unless e.cause.is_a?(PG::InFailedSqlTransaction)
        end
      end
    end

    def without_statement_timeout
      with_setting(:statement_timeout, 0) { yield }
    end
  end
end
