# frozen_string_literal: true

module SafePgMigrations
  module StatementReverter
    def invert_rename_table(args)
      [:rollback_rename_table, args]
    end
  end
end

ActiveRecord::Migration::CommandRecorder.prepend(SafePgMigrations::StatementReverter)
