# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    # This helper class allows to iterate over records in batches, in a similar
    # way to ActiveRecord's `in_batches` method with the :use_ranges option,
    # which was introduced in ActiveRecord 7.1, see:
    #
    #   - https://api.rubyonrails.org/classes/ActiveRecord/Batches.html#method-i-in_batches
    #   - https://github.com/rails/rails/blob/v7.1.0/activerecord/CHANGELOG.md
    #   - https://github.com/rails/rails/pull/45414
    #   - https://github.com/rails/rails/commit/620f24782977b8e53e06cf0e2c905a591936e990
    #
    # In ActiveRecord 8.1, `in_baches(use_ranges: true)` was optimized further
    # to use less cpu, memory, and bandwidth, see:
    #
    #   - https://github.com/rails/rails/releases/tag/v8.1.0
    #   - https://github.com/rails/rails/pull/51243
    #   - https://github.com/rails/rails/commit/c097bf6c24443323da8fe64030dd963951121dea
    #
    # If using ActiveRecord 8.1 or later, it's recommended to use the built-in
    # method, e.g.
    #
    #   User.in_batches(of: 100, use_ranges: true).each { |batch| ... }
    #
    # Otherwise, this helper can be used as a fallback:
    #
    #   SafePgMigrations::Helpers::BatchOver.new(User, of: 100).each_batch { |batch| ... }
    #
    class BatchOver
      def initialize(model, of: SafePgMigrations.config.backfill_batch_size)
        @model = model
        @of = of

        @current_range = nil
      end

      def each_batch
        yield scope.where(primary_key => @current_range) while next_batch
      end

      private

      def next_batch
        return if endless?

        first = next_scope.take

        return unless first

        last = next_scope.offset(@of).take

        first_key = first[primary_key]
        last_key = last.nil? ? nil : last[primary_key]

        @current_range = first_key...last_key
      end

      def next_scope
        return scope if @current_range.nil?
        return scope.none if endless?

        scope.where(primary_key => @current_range.end..)
      end

      def scope
        @model.order(primary_key => :asc)
      end

      def endless?
        return false if @current_range.nil?

        @current_range.end.nil?
      end

      def primary_key
        @model.primary_key
      end
    end
  end
end
