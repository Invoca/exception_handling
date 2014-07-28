require File.expand_path('../lib/exception_handling/version', __FILE__)

Gem::Specification.new do |gem|
  gem.add_dependency 'eventmachine', '>=0.12.10'
  gem.add_dependency 'activesupport', '~> 3.2'
  gem.add_dependency 'actionpack', '~> 3.2'
  gem.add_dependency 'actionmailer', '~> 3.2'
  gem.add_development_dependency 'rake', '>=0.9'
  gem.add_development_dependency 'shoulda', '=3.1.1'
  gem.add_development_dependency 'mocha', '=0.13.0'

  gem.authors       = ["Colin Kelley"]
  gem.email         = ["colindkelley@gmail.com"]
  gem.description   = %q{Exception handling logger/emailer}
  gem.summary       = %q{RingRevenue's exception handling logger/emailer layer, based on exception_notifier. Works with Rails or EventMachine or EventMachine+Synchrony.}
  gem.homepage      = "https://github.com/RingRevenue/exception_handling"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/.*\.rb})
  gem.name          = "exception_handling"
  gem.require_paths = ["lib"]
  gem.version       = ExceptionHandling::VERSION
end
