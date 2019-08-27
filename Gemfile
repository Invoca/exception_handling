# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in attr_default.gemspec
gemspec

gem 'actionmailer',  '>= 4.2.11.1'
gem 'actionpack',    '>= 4.2.11.1'
gem 'activesupport', '>= 4.2.11.1'
gem 'hobo_support',   '2.0.1',      git: 'git@github.com:Invoca/hobosupport',    ref: 'b9086322274b474a2b5bae507c4885e55d4aa050'
gem 'invoca-utils',                 git: 'git@github.com:Invoca/invoca-utils',   ref: '891b8f7e1af0f6324bf85601046907143122e204'

group :development do
  gem 'pry'
  gem 'rake',    '>=0.9'
  gem 'rr'
  gem 'rubocop'
  gem 'shoulda', '> 3.1.1'
end

group :test do
  gem 'honeybadger', '3.3.1-1', git: 'git@github.com:Invoca/honeybadger-ruby', ref: 'bb5f2b8a86e4147c38a6270d39ad610fab4dd5e6'
end
