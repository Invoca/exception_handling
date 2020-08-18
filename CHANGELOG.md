# CHANGELOG for `exception_handling`

Inspired by [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Note: this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.5.0] - Unreleased
### Added
- The `**log_context` passed to `log_error`/`log_warning`/`log_info` is now
  passed into `Honeybadger.notify()`, in `context: { log_context: ... }`.

## [2.4.3] - 2020-05-14
### Deprecated
- In `ExceptionHandling.logger=`, implicit `logger.extend ContextualLogger::LoggerMixin` is now deprecated.
  This will be removed in version 3.0 and an `ArgumentError` will be raised if the logger
  doesn't have that mixin. Instead of this implicit behavior, you should explicitly either `extend`
  your logger instance or `include` that mixin into your `Logger` class. 

## [2.4.2] - 2020-05-11
### Added
- Added support for rails 5 and 6.
- Added appraisal tests for all supported rails version: 4/5/6

### Changed
- Updated various test to be compatible with rails version 4/5/6
- Updated the CI pipeline to test against all three supported versions of rails

## [2.4.1] - 2020-04-29
### Changed
- No longer depends on hobo_support. Uses invoca-utils 0.3 instead.

[2.5.0]: https://github.com/Invoca/exception_handling/compare/v2.4.3...v2.5.0
[2.4.3]: https://github.com/Invoca/exception_handling/compare/v2.4.2...v2.4.3
[2.4.2]: https://github.com/Invoca/exception_handling/compare/v2.4.1...v2.4.2
[2.4.1]: https://github.com/Invoca/exception_handling/compare/v2.4.0...v2.4.1
