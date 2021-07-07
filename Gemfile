# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

gemspec

gem 'actionmailer', '< 6.1'
gem 'activesupport', '< 6.1'
gem 'appraisal', '~> 2.2'
gem 'honeybadger', '3.3.1-1', github: 'Invoca/honeybadger-ruby', ref: 'bb5f2b8a86e4147c38a6270d39ad610fab4dd5e6'
gem 'pry'
gem 'pry-byebug'
gem 'rake'
gem 'rspec'
gem 'rspec_junit_formatter'
gem 'rubocop'
gem 'test-unit'
