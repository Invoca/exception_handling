#!/usr/bin/env rake
require "bundler/gem_tasks"
require 'rake/testtask'

namespace :test do

  Rake::TestTask.new do |t|
    t.name = :unit
    t.libs << "test"
    t.pattern = 'test/unit/**/*_test.rb'
    t.verbose = true
  end
  Rake::Task['test:unit'].comment = "Run the unit tests"

end

task :default => 'test:unit'
