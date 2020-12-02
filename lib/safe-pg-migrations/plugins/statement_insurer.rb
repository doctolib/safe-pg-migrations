# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer
    PG_11_VERSION_NUM = 110_000

    %i[change_column_null change_column].each do |method|
      define_method method do |*args, &block|
        with_setting(:statement_timeout, SafePgMigrations.config.pg_safe_timeout) { super(*args, &block) }
      end
    end

    def add_column(table_name, column_name, type, **options) # rubocop:disable Metrics/CyclomaticComplexity
      need_default_value_backfill = SafePgMigrations.pg_version_num < PG_11_VERSION_NUM

      default = options.delete(:default) if need_default_value_backfill
      null = options.delete(:null)

      if !default.nil? || null == false
        SafePgMigrations.say_method_call(:add_column, table_name, column_name, type, options)
      end

      super

      if need_default_value_backfill && !default.nil?
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

    def add_foreign_key(from_table, to_table, **options)
      validate_present = options.key? :validate
      options[:validate] = false unless validate_present

      with_setting(:statement_timeout, SafePgMigrations.config.pg_safe_timeout) { super }

      options_or_to_table = options.slice(:name, :column).presence || to_table
      without_statement_timeout { validate_foreign_key from_table, options_or_to_table } unless validate_present
    end

    def create_table(*)
      with_setting(:statement_timeout, SafePgMigrations.config.pg_safe_timeout) do
        super do |td|
          yield td if block_given?
          td.indexes.map! do |key, index_options|
            index_options[:algorithm] ||= nil
            [key, index_options]
          end
        end
      end
    end

    def add_index(table_name, column_name, **options)
      if options.key? :algorithm
        options.delete :algorithm unless options[:algorithm]
      else
        options[:algorithm] = :concurrently
      end

      SafePgMigrations.say_method_call(:add_index, table_name, column_name, options)

      without_timeout { super }
    end

    def remove_index(table_name, options = {})
      options = { column: options } unless options.is_a?(Hash)
      options[:algorithm] = :concurrently
      SafePgMigrations.say_method_call(:remove_index, table_name, options)

      without_timeout { super }
    end

    def backfill_column_default(table_name, column_name)
      quoted_table_name = quote_table_name(table_name)
      quoted_column_name = quote_column_name(column_name)
      primary_key_offset = 0
      loop do
        ids = query_values <<~SQL.squish
          SELECT id FROM #{quoted_table_name} WHERE id > #{primary_key_offset}
          ORDER BY id LIMIT #{SafePgMigrations.config.batch_size}
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

    def without_lock_timeout
      with_setting(:lock_timeout, 0) { yield }
    end

    def without_timeout
      without_statement_timeout { without_lock_timeout { yield } }
    end
  end
end
