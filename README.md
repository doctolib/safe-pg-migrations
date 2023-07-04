# safe-pg-migrations

ActiveRecord migrations for Postgres made safe.

![safe-pg-migrations](./logo.png)

## Requirements

- Ruby 2.7+
- Rails 6.0+
- PostgreSQL 11.7+

## Usage

Just drop this line in your Gemfile:

```rb
gem 'safe-pg-migrations'
```

**Note: Do not run migrations via PgBouncer connection if it is configured to use transactional or statement pooling modes. You must run migrations via a direct Postgres connection, or configure PgBouncer to use session pooling mode.**

## Example

Consider the following migration:

```rb
class AddPatientRefToAppointments < ActiveRecord::Migration[6.0]
  def change
    add_reference :appointments, :patient
  end
end
```

If the `users` table is large, running this migration will likely cause downtime. **Safe PG Migrations** hooks into Active Record so that the following gets executed instead:

```rb
class AddPatientRefToAppointments < ActiveRecord::Migration[6.0]
  # Do not wrap the migration in a transaction so that locks are held for a shorter time.
  disable_ddl_transaction!

  def change
    # Lower Postgres' lock timeout to avoid statement queueing. Acts like a seatbelt.
    execute("SET lock_timeout TO '5s'")

    # Lower Postgres' statement timeout to avoid too long transactions. Acts like a seatbelt.
    execute("SET statement_timeout TO '5s'")
    add_column :appointments, :patient_id, :bigint

    # add_index using the concurrent algorithm, to avoid locking the tables
    add_index :appointments, :patient_id, algorithm: :concurrently

    # add_foreign_key without validation, to avoid locking the table for too long
    execute("SET statement_timeout TO '5s'")
    add_foreign_key :appointments, :patients, validate: false

    execute("SET statement_timeout TO '0'")

    # validate the foreign key separately, it avoids taking a lock on the entire tables
    validate_foreign_key :appointments, :patients
    
    # we also need to set timeouts to their initial values if needed
  end
end
```

Under the hood, **Safe PG Migrations** patches `ActiveRecord::Migration` and extends `ActiveRecord::Base.connection` to make potentially dangerous methods—like `add_reference`—safe.

## Motivation

Writing a safe migration can be daunting. Numerous articles, [including ours](https://medium.com/doctolib/stop-worrying-about-postgresql-locks-in-your-rails-migrations-3426027e9cc9), have been written on the topic and a few gems are trying to address the problem. Even for someone who has a pretty good command of Postgres, remembering all the subtleties of explicit locking is not a piece of cake.

Active Record means developers don't have to be proficient in SQL to interact with a database. In the same way, **Safe PG Migrations** was created so that developers don't have to understand the ins and outs of Postgres to write a safe migration.

## Feature set

<details><summary>Lock timeout</summary>

Most DDL operations (e.g. adding a column, removing a column or adding a default value to a column) take an `ACCESS EXCLUSIVE` lock on the table they are altering. While these operations wait to acquire their lock, other statements are blocked. Before running a migration, **Safe PG Migrations** sets a short lock timeout (default to 5 seconds) so that statements are not blocked for too long.

See [PostgreSQL Alter Table and Long Transactions](http://www.joshuakehn.com/2017/9/9/postgresql-alter-table-and-long-transactions.html) and [Migrations and Long Transactions](https://www.fin.com/post/2018/1/migrations-and-long-transactions) for detailed explanations of the matter.
</details>

<details><summary>Statement timeout</summary>

Adding a foreign key or a not-null constraint can take a lot of time on a large table. The problem is that those operations take `ACCESS EXCLUSIVE` locks. We clearly don't want them to hold these locks for too long. Thus, **Safe PG Migrations** runs them with a short statement timeout (default to 5 seconds).

See [Zero-downtime Postgres migrations - the hard parts](https://gocardless.com/blog/zero-downtime-postgres-migrations-the-hard-parts/) for a detailed explanation on the subject.
</details>

<details><summary>Prevent wrapping migrations in transaction</summary>

When **Safe PG Migrations** is used, migrations are not wrapped in a transaction. This is for several reasons:

- We want to release locks as soon as possible.
- In order to be able to retry statements that have failed because of a lock timeout, we have to be outside a transaction.
- In order to add an index concurrently, we have to be outside a transaction.

Note that if a migration fails, it won't be rolled back. This can result in migrations being partially applied. In that case, they need to be manually reverted.

</details>

<details>
<summary>Safe <code>add_column</code></summary>

**Safe PG Migrations** gracefully handle the upgrade to PG11 by **not** backfilling default value for existing rows, as the [database engine is now natively handling it](https://www.postgresql.org/docs/11/ddl-alter.html#DDL-ALTER-ADDING-A-COLUMN).

Beware though, when adding a volatile default value: 
```ruby
add_column :users, :created_at, default: 'clock_timestamp()'
```
PG will still needs to update every row of the table, and will most likely statement timeout for big table. In this case, **Safe PG Migrations** can automatically backfill data when the option `default_value_backfill:` is set to `:update_in_batches`. 

</details>

<details>
<summary>Safe add_column - adding a volatile default value</summary>

**Safe PG Migrations** provides the extra option parameter `default_value_backfill:`. When your migration is adding a volatile default value, the option `:update_in_batches` can be set. It will automatically backfill the value in a safe manner.

```ruby
safety_assured do
  add_column :users, :created_at, default: 'clock_timestamp()', default_value_backfill: :update_in_batches
end
```

More specifically, it will: 

1. create the column without default value and without null constraint. This ensure the `ACCESS EXCLUSIVE` lock is acquired for the least amount of time;
2. add the default value, without data backfill. An `ACCESS EXCLUSIVE` lock is acquired and released immediately;
3. backfill data, in batch of `SafePgMigrations.config.backfill_batch_size` and with a pause of `SafePgMigrations.config.backfill_pause` between each batch;
4. change the column to `null: false`, if defined in the parameters, following the algorithm we have defined below.

---
**NOTE**

Data backfill take time. If your table is big, your migrations will (safely) hangs for a while. You might want to backfill data manually instead, to do so you will need two migrations

1. First migration :

    a. adds the column without default and without null constraint;

    b. add the default value.

2. manual data backfill (rake task, manual operation, ...)
3. Second migration which change the column to null false (with **Safe PG Migrations**, `change_column_null` is safe and can be used; see section below)
---

`default_value_backfill:` also accept the value `:auto` which is set by default. In this case, **Safe PG Migrations** will not backfill data and will let PostgreSQL handle it itself.

### Preventing :update_in_batches when the table is too big

`add_column` with `default_value_backfill: :update_in_batches` can be dangerous on big tables. To avoid unwanted long migrations, **Safe PG Migrations** does not automatically mark this usage as safe when used with `strong-migrations`, usage of `safety_assured` is required.

It is also possible to set a threshold for the table size, above which the migration will fail. This can be done by setting the `default_value_backfill_threshold:` option in the configuration.


</details>

<details><summary id="safe_add_remove_index">Safe <code>add_index</code> and <code>remove_index</code></summary>

Creating an index requires a `SHARE` lock on the target table which blocks all write on the table while the index is created (which can take some time on a large table). This is usually not practical in a live environment. Thus, **Safe PG Migrations** ensures indexes are created concurrently.

As `CREATE INDEX CONCURRENTLY` and `DROP INDEX CONCURRENTLY` are non-blocking operations (ie: read/write operations on the table are still possible), **Safe PG Migrations** sets a lock timeout to 30 seconds for those 2 specific statements.

If you still get lock timeout while adding / removing indexes, it might be for one of those reasons:

- Long-running queries are active on the table. To create / remove an index, PG needs to wait for the queries that are actually running to finish before starting the index creation / removal. The blocking activity logger might help you to pinpoint the culprit queries.
- A vacuum / autovacuum is running on the table, holding a ShareUpdateExclusiveLock, you are most likely out of luck for the current migration, but you may try to [optimize your autovacuums settings](https://www.percona.com/blog/2018/08/10/tuning-autovacuum-in-postgresql-and-autovacuum-internals/).

</details>

<details><summary id="safe_add_foreign_key">Safe <code>add_foreign_key</code> (and <code>add_reference</code>)</summary>

Adding a foreign key requires a `SHARE ROW EXCLUSIVE` lock, which **prevent writing in the tables** while the migration is running.

Adding the constraint itself is rather fast, the major part of the time is spent on validating this constraint. Thus **Safe PG Migrations** ensures that adding a foreign key holds blocking locks for the least amount of time by splitting the foreign key creation in two steps: 

1. adding the constraint *without validation*, will not validate existing rows;
2. validating the constraint, will validate existing rows in the table, without blocking read or write on the table

</details>


<details><summary id="safe_add_check_constraint">Safe <code>add_check_constraint</code> (ActiveRecord > 6.1)</summary>

Adding a check constraint requires an `ACCESS EXCLUSIVE` lock, which **prevent writing and reading in the tables** [as soon as the lock is requested](https://medium.com/doctolib/stop-worrying-about-postgresql-locks-in-your-rails-migrations-3426027e9cc9).

Adding the constraint itself is rather fast, the major part of the time is spent on validating this constraint.
Thus **Safe PG Migrations** ensures that adding a constraints holds blocking locks for the least amount of time by
splitting the constraint addition in two steps: 

1. adding the constraint *without validation*, will not validate existing rows;
2. validating the constraint, will validate existing rows in the table, without blocking read or write on the table

</details>

<details><summary id="safe_change_column_null">Safe <code>change_column_null</code> (ActiveRecord and PG version dependant)</summary>

Changing the nullability of a column requires an `ACCESS EXCLUSIVE` lock, which **prevent writing and reading in the tables** [as soon as the lock is requested](https://medium.com/doctolib/stop-worrying-about-postgresql-locks-in-your-rails-migrations-3426027e9cc9).

Adding the constraint itself is rather fast, the major part of the time is spent on validating this constraint.

**Safe PG Migrations** acts differently depending on the version you are on. 

### Recent versions of PG and Active Record (> 12 and > 6.1)

Starting on PostgreSQL versions 12, adding the column NOT NULL constraint is safe if a check constraint validates the
nullability of the same column. **Safe PG Migrations** also relies on add_check_constraint, which was introduced in
ActiveRecord 6.1.  

If these requirements are met, **Safe PG Migrations** ensures that adding a constraints holds blocking locks for the least
amount of time by splitting the constraint addition in several steps: 

1. adding a `IS NOT NULL` constraint *without validation*, will not validate existing rows but block read or write;
2. validating the constraint, will validate existing rows in the table, without blocking read or write on the table;
3. changing the not null status of the column, thanks to the NOT NULL constraint without having to scan the table sequentially;
4. dropping the `IS NOT NULL` constraint.

### Older versions of PG or ActiveRecord

If the version of PostgreSQL is below 12, or if the version of ActiveRecord is below 6.1, **Safe PG Migrations** will only
wrap ActiveRecord method into a statement timeout and lock timeout.

### Call with a default parameter

Calling change_column_null with a default parameter [is dangerous](https://github.com/rails/rails/blob/716baea69f989b64f5bfeaff880c2512377bebab/activerecord/lib/active_record/connection_adapters/postgresql/schema_statements.rb#L446)
and is likely not to finish in the statement timeout defined by **Safe PG Migrations**. For this reason, when the default
parameter is given, **Safe PG Migrations** will simply forward it to activerecord methods without trying to improve it

### Dropping a NULL constraint

Dropping a null constraint still requires an `ACCESS EXCLUSIVE` lock, but does not require extra operation to reduce the
amount of time during which the lock is held. **Safe PG Migrations** only wrap methods of activerecord in lock and statement
timeouts

</details>



<details><summary>Retry after lock timeout</summary>

When a statement fails with a lock timeout, **Safe PG Migrations** retries it (5 times max) [list of retriable statements](https://github.com/doctolib/safe-pg-migrations/blob/66933256252b6bbf12e404b829a361dbba30e684/lib/safe-pg-migrations/plugins/statement_retrier.rb#L5)
</details>

<details><summary>Blocking activity logging</summary>

If a statement fails with a lock timeout, **Safe PG Migrations** will try to tell you what was the blocking statement.

---
**NOTE**

Data logged by the Blocking activity logger can be sensitive (it will contain raw SQL queries, which can be hashes of password, user information, ...)

If you cannot afford to log this type of data, you can either
* Set `SafePgMigrations.config.blocking_activity_logger_verbose = false`. In this case, the logger will only log the pid of the blocking statement, which should be enough to investigate;
* Provide a different logger through `SafePgMigrations.config.sensitive_logger = YourLogger.new`. Instead of using the default IO stream, SafePgMigrations will send sensitive data to the given logger which can be managed as you wish.

---

</details>

<details><summary>Verbose SQL logging</summary>

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
**Safe PG Migrations** will output the following logs:
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

</details>

## Configuration

**Safe PG Migrations** can be customized, here is an example of a Rails initializer (the values are the default ones):

```ruby
SafePgMigrations.config.safe_timeout = 5.seconds # Statement timeout used for all DDL operations except from CREATE / DROP INDEX

SafePgMigrations.config.lock_timeout = nil # Lock timeout used for all DDL operations except from CREATE / DROP INDEX. If not set, safe_timeout will be used with a deduction of 1% to ensure that the lock timeout is raised in priority

SafePgMigrations.config.blocking_activity_logger_verbose = true # Outputs the raw blocking queries on timeout. When false, outputs information about the lock instead

SafePgMigrations.config.sensitive_logger = nil # When given, sensitive data will be sent to this logger instead of the standard output. Must implement method `info`.

SafePgMigrations.config.blocking_activity_logger_margin = 1.second # Delay to output blocking queries before timeout. Must be shorter than safe_timeout

SafePgMigrations.config.backfill_batch_size = 100_000 # Size of the batches used for backfilling when adding a column with a default value

SafePgMigrations.config.backfill_pause = 0.5.second # Delay between each batch during a backfill. This ensure replication can happen safely. 

SafePgMigrations.config.default_value_backfill_threshold = nil # When set, batch backfill will only be available if the table is under the given threshold. If the number of rows is higher, the migration will fail. 

SafePgMigrations.config.retry_delay = 1.minute # Delay between retries for retryable statements

SafePgMigrations.config.max_tries = 5 # Number of retries before abortion of the migration
```

## Running tests

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

- [When Postgres blocks: 7 tips for dealing with locks](https://www.citusdata.com/blog/2018/02/22/seven-tips-for-dealing-with-postgres-locks/)
- [Migrations and Long Transactions in Postgres
](https://www.fin.com/post/2018/1/migrations-and-long-transactions)
- [PostgreSQL Alter Table and Long Transactions](http://www.joshuakehn.com/2017/9/9/postgresql-alter-table-and-long-transactions.html)
- [Adding a NOT NULL CONSTRAINT on PG Faster with Minimal Locking](https://medium.com/doctolib-engineering/adding-a-not-null-constraint-on-pg-faster-with-minimal-locking-38b2c00c4d1c)
- [Adding columns with default values to really large tables in Postgres + Rails](https://wework.github.io/data/2015/11/05/add-columns-with-default-values-to-large-tables-in-rails-postgres/)
- [Rails migrations with no downtime](https://pedro.herokuapp.com/past/2011/7/13/rails_migrations_with_no_downtime/)
- [Safe Operations For High Volume PostgreSQL](https://www.braintreepayments.com/blog/safe-operations-for-high-volume-postgresql/)
- [Rails Migrations with Zero Downtime](https://blog.codeship.com/rails-migrations-zero-downtime/)
- [Stop worrying about PostgreSQL locks in your Rails migrations](https://medium.com/doctolib/stop-worrying-about-postgresql-locks-in-your-rails-migrations-3426027e9cc9)
- [PostgreSQL at Scale: Database Schema Changes Without Downtime](https://medium.com/paypal-tech/postgresql-at-scale-database-schema-changes-without-downtime-20d3749ed680)
