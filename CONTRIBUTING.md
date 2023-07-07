# Contributing

## Running tests

```bash
bundle
psql -h localhost -c 'CREATE DATABASE safe_pg_migrations_test'
rake test
```

You may want to use one of the specific gemfiles, to test against some exotic setups. To do so, run: 

```bash
BUNDLE_GEMFILE=gemfiles/<YOUR GEMFILE> bundle
BUNDLE_GEMFILE=gemfiles/<YOUR GEMFILE> bundle exec rake test
```

## Releasing

### Automatic release message

Automatic release message can be generated using [GitHub's release tool](https://github.com/doctolib/safe-pg-migrations/releases/new).
It is configured via [`.github/release.yml`](.github/release.yml).

* Any pull request merged with labels `ignore-for-release` or `dependencies` will be ignored.
* Pull requests released with label `breaking-change` will be gathered in the "Breaking changes" section.
* Pull requests released with label `bug` will be gathered in the "Bug fixes" section.
* Any other release will be added to the "New features" section.

### Release process

--- 
**NOTE**

You need to be part of Doctolib to release a new version of this gem.

---

1. Create a pull request and update the tag:
    ```bash
      vim lib/safe-pg-migrations/version.rb # Or whatever editor you'd like
      bundle # to update the gem version in Gemfile.lock
    ```
2. Pull master on your computer, and generate the new `gem` file:
    ```bash
    bundle
    gem build safe-pg-migrations.gemspec
    # This pushed the new gem version to RubyGem.  You will probably be asked your TOTP code at this step
    gem push safe-pg-migrations-<VERSION>.gem
    ```
3. Once the pull request is merged, create a new release on GitHub.
    a. Click on [GitHub's release tool](https://github.com/doctolib/safe-pg-migrations/releases/new);
    b. Click on "Choose a tag" and write the name of your new tag (using semantic versioning). A button will appear to create the new tag;
    c. Once the tag is created, feel the release title with your tag name as well;
    d. Click on "Generate release notes"
    e. Ensure that "Set as the latest release" is checked
    f. Upload the `gem` file you generated in step 2
    e. Click on "Publish release"
