# safe-pg-migrations

[![Build Status](https://travis-ci.org/doctolib/safe-pg-migrations.svg?branch=master)](https://travis-ci.org/doctolib/safe-pg-migrations)

## Compatibility

Ruby 2.3+  
Rails 5.2+  
PostgreSQL 9.3+

## Running tests

```bash
bundle
psql -h localhost -c 'CREATE DATABASE safe_pg_migrations_test'
rake test
```
