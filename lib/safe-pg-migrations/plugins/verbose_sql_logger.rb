# frozen_string_literal: true

module SafePgMigrations
  class VerboseSqlLogger
    def setup
      @activerecord_logger_was = ActiveRecord::Base.logger
      @verbose_query_logs_was = Polyfills::VerboseQueryLogsPolyfill.verbose_query_logs
      @colorize_logging_was = ActiveRecord::LogSubscriber.colorize_logging

      disable_marginalia if defined?(Marginalia)

      stdout_logger = Logger.new($stdout, formatter: ->(_severity, _time, _progname, query) { "#{query}\n" })
      ActiveRecord::Base.logger = stdout_logger
      ActiveRecord::LogSubscriber.colorize_logging = colorize_logging?
      # Do not output caller method, we know it is coming from the migration
      Polyfills::VerboseQueryLogsPolyfill.verbose_query_logs = false
      self
    end

    def teardown
      Polyfills::VerboseQueryLogsPolyfill.verbose_query_logs = @verbose_query_logs_was
      ActiveRecord::LogSubscriber.colorize_logging = @colorize_logging_was
      ActiveRecord::Base.logger = @activerecord_logger_was
      enable_marginalia if defined?(Marginalia)
    end

    private

    def colorize_logging?
      defined?(Rails) && Rails.env.development?
    end

    # Marginalia annotations will most likely pollute the output
    def disable_marginalia
      @marginalia_components_were = Marginalia::Comment.components
      Marginalia::Comment.components = []
    end

    def enable_marginalia
      Marginalia::Comment.components = @marginalia_components_were
    end
  end
end
