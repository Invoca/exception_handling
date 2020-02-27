#!/usr/bin/env rake
# frozen_string_literal: true

require "bundler/gem_tasks"
require 'rake/testtask'

namespace :test do
  Rake::TestTask.new do |t|
    t.pattern = "test/**/*_test.rb"
  end
end

task test: 'test:unit'
task default: 'test'
