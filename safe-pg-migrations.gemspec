# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'safe-pg-migrations/version'

Gem::Specification.new do |s|
  s.name        = 'safe-pg-migrations'
  s.summary     = 'Make your PG migrations safe.'
  s.description = 'Make your PG migrations safe.'

  s.version = SafePgMigrations::VERSION

  s.authors  = ['Matthieu Prat', 'Romain Choquet']
  s.email    = 'matthieuprat@gmail.com'
  s.homepage = 'https://github.com/doctolib/safe-pg-migrations'

  s.files        = Dir['LICENSE', 'README.md', 'lib/**/*']
  s.require_path = 'lib'

  s.license = 'MIT'

  s.platform              = Gem::Platform::RUBY
  s.required_ruby_version = '>= 2.4'
end
