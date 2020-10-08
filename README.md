# safe-pg-migrations

ActiveRecord migrations for Postgres made safe.

## Requirements

- Ruby 2.5+
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

If the `users` table is large, running this migration on a live Postgres 9 database will likely cause downtime. **Safe PG Migrations** hooks into Active Record so that the following gets executed instead:

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

Most DDL operations (e.g. adding a column, removing a column or adding a default value to a column) take an `ACCESS EXCLUSIVE` lock on the table they are altering. While these operations wait to acquire their lock, other statements are blocked. Before running a migration, **Safe PG Migrations** sets a short lock timeout (default to 5 seconds) so that statements are not blocked for too long.

See [PostgreSQL Alter Table and Long Transactions](http://www.joshuakehn.com/2017/9/9/postgresql-alter-table-and-long-transactions.html) and [Migrations and Long Transactions](https://www.fin.com/post/2018/1/migrations-and-long-transactions) for detailed explanations of the matter.

### Statement timeout

Adding a foreign key or a not-null constraint can take a lot of time on a large table. The problem is that those operations take `ACCESS EXCLUSIVE` locks. We clearly don't want them to hold these locks for too long. Thus, **Safe PG Migrations** runs them with a short statement timeout (default to 5 seconds).

See [Zero-downtime Postgres migrations - the hard parts](https://gocardless.com/blog/zero-downtime-postgres-migrations-the-hard-parts/) for a detailed explanation on the subject.

### Prevent wrapping migrations in transaction

When **Safe PG Migrations** is used, migrations are not wrapped in a transaction. This is for several reasons:

- We want to release locks as soon as possible.
- In order to be able to retry statements that have failed because of a lock timeout, we have to be outside a transaction.
- In order to add an index concurrently, we have to be outside a transaction.

Note that if a migration fails, it won't be rollbacked. This can result in migrations being partially applied. In that case, they need to be manually reverted.

### Safe `add_column`

<details><summary>details</summary>

#### Pre Postgres 11 behavior

Adding a column with a default value and a not-null constraint is [dangerous](https://wework.github.io/data/2015/11/05/add-columns-with-default-values-to-large-tables-in-rails-postgres/).

**Safe PG Migrations** makes it safe by:

1.  Adding the column without the default value and the not null constraint,
2.  Then set the default value on the column,
3.  Then backfilling the column,
4.  And then adding the not null constraint with a short statement timeout.

Note: the addition of the not null constraint may timeout. In that case, you may want to add the not-null constraint as initially not valid and validate it in a separate statement. See [Adding a not-null constraint on Postgres with minimal locking](https://medium.com/doctolib-engineering/adding-a-not-null-constraint-on-pg-faster-with-minimal-locking-38b2c00c4d1c).

#### Postgres 11 behavior

**Safe PG Migrations** gracefully handle the upgrade to PG11 by **not** backfilling default value for existing rows, as the [database engine is now natively handling it](https://www.postgresql.org/docs/11/ddl-alter.html#DDL-ALTER-ADDING-A-COLUMN).

Beware though, when adding a volatile default value: 
```ruby
add_column :users, :created_at, default: 'clock_timestamp()'
```
PG will still needs to update every row of the table, and will most likely statement timeout for big table. In this case, your best bet is to add the column without default, set the default, and backfill existing rows.
</details>

### Concurrent indexes

Creating an index requires a `SHARE` lock on the target table which blocks all write on the table while the index is created (which can take some time on a large table). This is usually not practical in a live environment. Thus, **Safe PG Migrations** ensures indexes are created concurrently.

As `CREATE INDEX CONCURRENTLY` and `DROP INDEX CONCURRENTLY` are non-blocking operations (ie: read/write operations on the table are still possible), **Safe PG Migrations** sets a lock timeout to 30 seconds for those 2 specific statements.

If you still get lock timeout while adding / removing indexes, it might be for one of those reasons:

- Long-running queries are active on the table. To create / remove an index, PG needs to wait for the queries that are actually running to finish before starting the index creation / removal. The blocking activity logger might help you to pinpoint the culprit queries.
- A vacuum / autovacuum is running on the table, holding a ShareUpdateExclusiveLock, you are most likely out of luck for the current migration, but you may try to [optimize your autovacuums settings](https://www.percona.com/blog/2018/08/10/tuning-autovacuum-in-postgresql-and-autovacuum-internals/).


### Retry after lock timeout

When a statement fails with a lock timeout, **Safe PG Migrations** retries it (5 times max) [list of retryable statments](https://github.com/doctolib/safe-pg-migrations/blob/66933256252b6bbf12e404b829a361dbba30e684/lib/safe-pg-migrations/plugins/statement_retrier.rb#L5)

### Blocking activity logging

If a statement fails with a lock timeout, **Safe PG Migrations** will try to tell you what was the blocking statement.

### Verbose SQL logging

For any operation, **Safe PG Migrations** can output the performed SQL queries. This feature is enabled by default in a production Rails environment. If you want to explicit enable it, for example in your development environment you can use:
```bash
export SAFE_PG_MIGRATIONS_VERBOSE=1
```

Instead of the traditional output:
```ruby
add_index :users, :age

== 20191215132355 SampleIndex: migrating ======================================
-- add_index(:users, :age)
   -> add_index("users", :age, {:algorithm=>:concurrently})
   -> 0.0175s
== 20191215132355 SampleIndex: migrated (0.0200s) =============================
```
**Sage PG Migrations** will output the following logs:
```ruby
add_index :users, :age

== 20191215132355 SampleIndex: migrating ======================================
   (0.3ms)  SHOW lock_timeout
   (0.3ms)  SET lock_timeout TO '5s'
-- add_index(:users, :age)
   -> add_index("users", :age, {:algorithm=>:concurrently})
   (0.3ms)  SHOW statement_timeout
   (0.3ms)  SET statement_timeout TO 0
   (0.3ms)  SHOW lock_timeout
   (0.3ms)  SET lock_timeout TO '30s'
   (3.5ms)  CREATE INDEX CONCURRENTLY "index_users_on_age" ON "users"  ("age")
   (0.3ms)  SET lock_timeout TO '5s'
   (0.2ms)  SET statement_timeout TO '1min'
   -> 0.0093s
   (0.2ms)  SET lock_timeout TO '0'
== 20191215132355 SampleIndex: migrated (0.0114s) =============================
```
So you can actually check that the `CREATE INDEX` statement will be performed concurrently, without any statement timeout and with a lock timeout of 30 seconds.

*Nb: The `SHOW` statements are used by **Safe PG Migrations** to query settings for their original values in order to restore them after the work is done*

## Configuration

**Safe PG Migrations** can be customized, here is an example of a Rails initializer (the values are the default ones):

```ruby
SafePgMigrations.config.safe_timeout = 5.seconds # Lock and statement timeout used for all DDL operations except from CREATE / DROP INDEX

SafePgMigrations.config.index_lock_timeout = 30.seconds # Lock timeout used for CREATE / DROP INDEX

SafePgMigrations.config.blocking_activity_logger_margin = 1.second # Delay to output blocking queries before timeout. Must be smaller than safe_timeout and index_lock_timeout

SafePgMigrations.config.batch_size = 1000 # Size of the batches used for backfilling when adding a column with a default value pre-PG11

SafePgMigrations.config.retry_delay = 1.minute # Delay between retries for retryable statements

SafePgMigrations.config.max_tries = 5 # Number of retries before abortion of the migration
```

## Runnings tests

```bash
bundle
psql -h localhost -U postgres -c 'CREATE DATABASE safe_pg_migrations_test'
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

- [When Postgres blocks: 7 tips for dealing with locks](https://www.citusdata.com/blog/2018/02/22/seven-tips-for-dealing-with-postgres-locks/)
- [Migrations and Long Transactions in Postgres
](https://www.fin.com/post/2018/1/migrations-and-long-transactions)
- [PostgreSQL Alter Table and Long Transactions](http://www.joshuakehn.com/2017/9/9/postgresql-alter-table-and-long-transactions.html)
- [Adding a NOT NULL CONSTRAINT on PG Faster with Minimal Locking](https://medium.com/doctolib-engineering/adding-a-not-null-constraint-on-pg-faster-with-minimal-locking-38b2c00c4d1c)
- [Adding columns with default values to really large tables in Postgres + Rails](https://wework.github.io/data/2015/11/05/add-columns-with-default-values-to-large-tables-in-rails-postgres/)
- [Rails migrations with no downtime](https://pedro.herokuapp.com/past/2011/7/13/rails_migrations_with_no_downtime/)
- [Safe Operations For High Volume PostgreSQL](https://www.braintreepayments.com/blog/safe-operations-for-high-volume-postgresql/)
- [Rails Migrations with Zero Downtime](https://blog.codeship.com/rails-migrations-zero-downtime/)
