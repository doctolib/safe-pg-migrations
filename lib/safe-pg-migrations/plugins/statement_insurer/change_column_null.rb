# frozen_string_literal: true

module SafePgMigrations
  module StatementInsurer
    module ChangeColumnNull
      def change_column_null(table_name, column_name, null, default = nil)
        return super unless should_create_constraint? default, null

        expression = "#{column_name} IS NOT NULL"
        # constraint will be defined if the constraint was manually created in another migration
        constraint = check_constraint_by_expression table_name, expression

        default_name = check_constraint_name(table_name, expression: expression)
        constraint_name = constraint&.name || default_name

        add_check_constraint table_name, expression, name: constraint_name

        Helpers::Logger.say_method_call :change_column_null, table_name, column_name, false
        super table_name, column_name, false

        return unless should_remove_constraint? default_name, constraint_name

        Helpers::Logger.say_method_call :remove_check_constraint, table_name, expression, name: constraint_name
        remove_check_constraint table_name, expression, name: constraint_name
      end

      private

      def check_constraint_by_expression(table_name, expression)
        check_constraints(table_name).detect { |check_constraint| check_constraint.expression == expression }
      end

      def should_create_constraint?(default, null)
        !default && !null && Helpers::SatisfiedHelper.satisfies_change_column_null_requirements?
      end

      def should_remove_constraint?(default_name, constraint_name)
        # we don't want to remove the constraint if it was created in another migration. The best guess we have here is
        # that manually created constraint would likely have a name that is not the default name. This is not a perfect,
        # a manually created constraint without a name would be removed. However, it is now replaced by the NOT NULL
        # statement on the table, so this is not a big issue.
        default_name == constraint_name
      end
    end
  end
end
