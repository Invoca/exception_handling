#!/usr/bin/env rake
# frozen_string_literal: true

require "bundler/gem_tasks"
require 'rake/testtask'

require_relative 'test/rake_test_warning_false'

task default: :test

Rake::TestTask.new do |t|
  t.pattern = "test/**/*_test.rb"
end

