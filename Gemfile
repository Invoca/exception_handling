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
gem 'honeybadger', '~> 4.11'
gem 'pry'
gem 'pry-byebug'
gem 'rake'
gem 'rspec'
gem 'rspec_junit_formatter'
gem 'rubocop'
gem 'test-unit'
