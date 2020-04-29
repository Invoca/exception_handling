# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in attr_default.gemspec
gemspec

gem 'actionmailer'
gem 'actionpack'
gem 'activesupport'

group :development do
  gem "minitest"
  gem "minitest-reporters"
  gem 'pry'
  gem 'rake',    '>=0.9'
  gem 'rr'
  gem 'rubocop'
  gem 'shoulda', '> 3.1.1'
end

group :test do
  gem 'honeybadger', '3.3.1-1', git: 'git@github.com:Invoca/honeybadger-ruby', ref: 'bb5f2b8a86e4147c38a6270d39ad610fab4dd5e6'
  gem 'invoca-utils', '~> 0.3'
end
