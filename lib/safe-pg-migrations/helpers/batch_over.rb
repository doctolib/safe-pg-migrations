# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    class BatchOver
      def initialize(model, of: SafePgMigrations.config.backfill_batch_size)
        @model = model
        @of = of

        @current_batch = nil
      end

      def in_batches
        yield @model.order(primary_key => :asc).where(primary_key => @current_batch) while next_batch
      end

      private

      def next_batch
        return if endless?

        scope = @model.order(primary_key => :asc).select(primary_key)
        scope = scope.where(primary_key => @current_batch.end..) unless @current_batch.nil?

        first = scope.take

        return unless first

        last = scope.offset(@of).take

        first_key = first[primary_key]
        last_key = last.nil? ? nil : last[primary_key]

        @current_batch = first_key...last_key
      end

      def endless?
        return false if @current_batch.nil?

        @current_batch.end.nil?
      end

      def primary_key
        @model.primary_key
      end
    end
  end
end
