# safe-pg-migrations [![Build Status](https://travis-ci.org/doctolib/safe-pg-migrations.svg?branch=master)](https://travis-ci.org/doctolib/safe-pg-migrations)

ActiveRecord migrations for Postgres made safe.

## Requirements

- Ruby 2.3+
- Rails 5.2+
- PostgreSQL 9.3+

## Usage

Just drop this line in your Gemfile:

```rb
gem 'safe-pg-migrations'
```

## Example

Consider the following migration:

```rb
class AddAdminToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :admin, :boolean, default: false, null: false
  end
end
```

If the `users` table is large, running this migration on a live Postgres database will likely cause downtime. **Safe PG Migrations** hooks into Active Record so that the following gets executed instead:

```rb
class AddAdminToUsers < ActiveRecord::Migration[5.2]
  # Do not wrap the migration in a transaction so that locks are held for a shorter time.
  disable_ddl_transaction!

  def change
    # Lower Postgres' lock timeout to avoid statement queueing. Acts like a seatbelt.
    execute "SET lock_timeout TO '5s'" # The lock_timeout duration is customizable.

    # Add the column without the default value and the not-null constraint.
    add_column :users, :admin, :boolean

    # Set the column's default value.
    change_column_default :users, :admin, false

    # Backfill the column in batches.
    User.in_batches.update_all(admin: false)

    # Add the not-null constraint. Beforehand, set a short statement timeout so that
    # Postgres does not spend too much time performing the full table scan to verify
    # the column contains no nulls.
    execute "SET statement_timeout TO '5s'"
    change_column_null :users, :admin, false
  end
end
```

Under the hood, **Safe PG Migrations** patches `ActiveRecord::Migration` and extends `ActiveRecord::Base.connection` to make potentially dangerous methods—like `add_column`—safe.

## Motivation

Writing a safe migration can be daunting. Numerous articles have been written on the topic and a few gems are trying to address the problem. Even for someone who has a pretty good command of Postgres, remembering all the subtleties of explicit locking is not a piece of cake.

Active Record means developers don't have to be proficient in SQL to interact with a database. In the same way, **Safe PG Migrations** was created so that developers don't have to understand the ins and outs of Postgres to write a safe migration.

## Feature set

### Lock timeout

Most DDL operations (e.g. adding a column, removing a column or adding a default value to a column) take an `ACCESS EXCLUSIVE` lock on the table they are altering. While these operations wait to acquire their lock, other statements are blocked. Before running a migration, **Safe PG Migrations** sets a short lock timeout so that statements are not blocked for too long.

See [PostgreSQL Alter Table and Long Transactions](http://www.joshuakehn.com/2017/9/9/postgresql-alter-table-and-long-transactions.html) and [Migrations and Long Transactions](https://www.fin.com/post/2018/1/migrations-and-long-transactions) for detailed explanations of the matter.

### Statement timeout

Adding a foreign key or a not-null constraint can take a lot of time on a large table. The problem is that those operations take `ACCESS EXCLUSIVE` locks. We clearly don't want them to hold these locks for too long. Thus, **Safe PG Migrations** runs them with a short statement timeout.

See [Zero-downtime Postgres migrations - the hard parts](https://gocardless.com/blog/zero-downtime-postgres-migrations-the-hard-parts/) for a detailed explanation on the subject.

### Prevent wrapping migrations in transaction

When **Safe PG Migrations** is enabled (which is the case by default if `Rails.env.production?` is true), migrations are not wrapped in a transaction. This is for several reasons:

- We want to release locks as soon as possible.
- In order to be able to retry statements that have failed because of a lock timeout, we have to be outside a transaction.
- In order to add an index concurrently, we have to be outside a transaction.

Note that if a migration fails, it won't be rollbacked. This can result in migrations being partially applied. In that case, they need to be manually reverted.

### Safe `add_column`

Adding a column with a default value and a not-null constraint is [dangerous](https://wework.github.io/data/2015/11/05/add-columns-with-default-values-to-large-tables-in-rails-postgres/).

**Safe PG Migrations** makes it safe by:

1.  Adding the column without the default value and the not null constraint,
2.  Then set the default value on the column,
3.  Then backfilling the column,
4.  And then adding the not null constraint with a short statement timeout.

Note: the addition of the not null constraint may timeout. In that case, you may want to add the not-null constraint as initially not valid and validate it in a separate statement. See [Adding a not-null constraint on Postgres with minimal locking](https://medium.com/doctolib-engineering/adding-a-not-null-constraint-on-pg-faster-with-minimal-locking-38b2c00c4d1c).

### Concurrent indexes

Creating an index requires a `SHARE` lock on the target table which blocks all write on the table while the index is created (which can take some time on a large table). This is usually not practical in a live environment. Thus, **Safe PG Migrations** ensures indexes are created concurrently.

### Retry after lock timeout

When a statement fails with a lock timeout, **Safe PG Migrations** retries them (5 times max).

### Blocking activity logging

If a statement fails with a lock timeout, **Safe PG Migrations** will try to tell you what was the blocking statement.

## Runnings tests

```bash
bundle
psql -h localhost -c 'CREATE DATABASE safe_pg_migrations_test'
rake test
```

## Authors

- [Matthieu Prat](https://github.com/matthieuprat)
- [Romain Choquet](https://github.com/rchoquet)
- [Paul-Etienne Coisne](https://github.com/coisnepe)

## License

[MIT](https://github.com/doctolib/safe-pg-migrations/blob/master/LICENSE) © [Doctolib](https://github.com/doctolib/)

## Additional resources

Alternatives:

- https://github.com/gocardless/activerecord-safer_migrations
- https://github.com/ankane/strong_migrations
- https://github.com/LendingHome/zero_downtime_migrations

Interesting reads:

- https://www.citusdata.com/blog/2018/02/22/seven-tips-for-dealing-with-postgres-locks/
- https://www.fin.com/post/2018/1/migrations-and-long-transactions
- http://www.joshuakehn.com/2017/9/9/postgresql-alter-table-and-long-transactions.html
- https://medium.com/doctolib-engineering/adding-a-not-null-constraint-on-pg-faster-with-minimal-locking-38b2c00c4d1c
- https://wework.github.io/data/2015/11/05/add-columns-with-default-values-to-large-tables-in-rails-postgres/
- https://pedro.herokuapp.com/past/2011/7/13/rails_migrations_with_no_downtime/
- https://www.braintreepayments.com/blog/safe-operations-for-high-volume-postgresql/
- https://blog.codeship.com/rails-migrations-zero-downtime/
