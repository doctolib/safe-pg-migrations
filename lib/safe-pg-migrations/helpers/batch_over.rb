# frozen_string_literal: true

module SafePgMigrations
  module Helpers
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

        first = next_scope.select(primary_key).take

        return unless first

        last = next_scope.select(primary_key).offset(@of).take

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
