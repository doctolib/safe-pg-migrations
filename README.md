# safe-pg-migrations

## Compatibility

Rails 5.2+
PostgreSQL 9.6+

## Running tests

```bash
bundle
psql postgres://localhost -c 'CREATE DATABASE safe_pg_migrations_test'
rake test
```
