# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'safe-pg-migrations/version'

Gem::Specification.new do |s|
  s.name        = 'safe-pg-migrations'
  s.summary     = 'Make your PG migrations safe.'
  s.description = 'Make your PG migrations safe.'

  s.version = SafePgMigrations::VERSION

  s.authors  = ['Matthieu Prat', 'Romain Choquet', 'Thomas Hareau']
  s.homepage = 'https://github.com/doctolib/safe-pg-migrations'

  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/doctolib/safe-pg-migrations/issues',
    'homepage_uri' => 'https://github.com/doctolib/safe-pg-migrations#safe-pg-migrations',
    'mailing_list_uri' => 'https://doctolib.engineering/engineering-news-ruby-rails-react',
    'source_code_uri' => 'https://github.com/doctolib/safe-pg-migrations',
    'contributors_uri' => 'https://github.com/doctolib/safe-pg-migrations/graphs/contributors',
  }

  s.files        = Dir['LICENSE', 'README.md', 'lib/**/*']
  s.require_path = 'lib'

  s.license = 'MIT'

  s.platform              = Gem::Platform::RUBY
  s.required_ruby_version = '>= 2.5', '< 4'

  s.add_dependency 'activerecord', '>= 5.2'
  s.add_dependency 'activesupport', '>= 5.2'
  s.add_dependency 'ruby2_keywords', '>= 0.0.4'

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'mocha'
  s.add_development_dependency 'pg'
  s.add_development_dependency 'pry'
  s.add_development_dependency 'pry-coolline'
  s.add_development_dependency 'rake'
end
