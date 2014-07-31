require File.expand_path('../lib/exception_handling/version', __FILE__)

Gem::Specification.new do |spec|
  spec.authors       = ["Colin Kelley"]
  spec.email         = ["colindkelley@gmail.com"]
  spec.description   = %q{Exception handling logger/emailer}
  spec.summary       = %q{Invoca's exception handling logger/emailer layer, based on exception_notifier. Works with Rails or EventMachine or EventMachine+Synchrony.}
  spec.homepage      = "https://github.com/Invoca/exception_handling"

  spec.files         = `git ls-files`.split($\)
  spec.executables   = spec.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/.*\.rb})
  spec.name          = "exception_handling"
  spec.require_paths = ["lib"]
  spec.version       = ExceptionHandling::VERSION

  spec.add_dependency 'eventmachine', '>=0.12.10'
  spec.add_dependency 'activesupport', '~> 3.2'
  spec.add_dependency 'actionpack', '~> 3.2'
  spec.add_dependency 'actionmailer', '~> 3.2'
  spec.add_dependency 'invoca-utils', '~> 0.0.1'
  spec.add_dependency 'invoca-metrics'
  spec.add_dependency 'hobo_support'
  spec.add_development_dependency 'rake', '>=0.9'
  spec.add_development_dependency 'shoulda', '=3.1.1'
  spec.add_development_dependency 'rr'
  spec.add_development_dependency 'pry'
end
