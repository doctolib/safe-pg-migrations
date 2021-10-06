# frozen_string_literal: true

module SafePgMigrations
  module CommandRecorder
    # When reverting a migration with `rename_table`, use a different method
    # to revert table renaming.
    # This overrides the original implementation that records `rename_table`
    # with reverted arguments (rename new table name to old table name).
    def invert_rename_table(args)
      [:revert_rename_table, args]
    end
  end
end
