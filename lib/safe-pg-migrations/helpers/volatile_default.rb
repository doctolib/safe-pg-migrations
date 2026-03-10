# frozen_string_literal: true

module SafePgMigrations
  module Helpers
    module VolatileDefault
      VOLATILE_DEFAULT_PATTERNS = [
        /\bclock_timestamp\s*\(/i,
        /\bnow\s*\(/i,
        /\bcurrent_timestamp\b/i,
        /\bcurrent_time\b/i,
        /\bcurrent_date\b/i,
        /\brandom\s*\(/i,
        /\buuid_generate/i,
        /\bgen_random_uuid\s*\(/i,
        /\btimeofday\s*\(/i,
        /\btransaction_timestamp\s*\(/i,
        /\bstatement_timestamp\s*\(/i,
        /\bnextval\s*\(/i,
        /\btxid_current\s*\(/i,
        /\bpg_current_xact_id\s*\(/i,
        /\bgen_random_bytes\s*\(/i,
        /\binet_client_addr\s*\(/i,
        /\binet_server_addr\s*\(/i,
        /\bpg_backend_pid\s*\(/i,
      ].freeze

      module_function

      def volatile_default?(default)
        return false if default.nil?
        return true if default.is_a?(Proc)
        return false unless default.is_a?(String)

        VOLATILE_DEFAULT_PATTERNS.any? { |pattern| default.match?(pattern) }
      end
    end
  end
end
