# frozen_string_literal: true

# Rake 11+ has a misfeature where @warning = true by default
# See https://github.com/ruby/rake/pull/97/files
# This causes all tests to be run with `ruby -w`, causing a huge number of warnings
# from gems we don't control and overwhelming our test output.
# This patch reverts that.

_ = Rake::TestTask

class Rake::TestTask
  module SetWarningFalseMixin
    def initialize(*args)
      super
      self.warning = false
    end
  end

  prepend SetWarningFalseMixin
end
