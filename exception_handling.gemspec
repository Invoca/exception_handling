# frozen_string_literal: true

require File.expand_path('lib/exception_handling/version', __dir__)

Gem::Specification.new do |spec|
  spec.authors       = ["Invoca"]
  spec.email         = ["development@invoca.com"]
  spec.description   = 'Exception handling logger/emailer'
  spec.summary       = "Invoca's exception handling logger/emailer layer, based on exception_notifier. Works with Rails or EventMachine or EventMachine+Synchrony."
  spec.homepage      = "https://github.com/Invoca/exception_handling"

  spec.files         = `git ls-files`.split("\n")
  spec.executables   = spec.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/.*\.rb})
  spec.name          = "exception_handling"
  spec.require_paths = ["lib"]
  spec.version       = ExceptionHandling::VERSION
  spec.metadata    = {
    "source_code_uri"   => "https://github.com/Invoca/exception_handling",
    "allowed_push_host" => "https://rubygems.org"
  }

  spec.add_dependency 'actionmailer',      '>= 4.2', '< 7.0'
  spec.add_dependency 'actionpack',        '>= 4.2', '< 7.0'
  spec.add_dependency 'activesupport',     '>= 4.2', '< 7.0'
  spec.add_dependency 'contextual_logger', '~> 0.7'
  spec.add_dependency 'escalate',          '~> 0.1'
  spec.add_dependency 'eventmachine',      '~> 1.0'
  spec.add_dependency 'invoca-utils',      '~> 0.3'
end
