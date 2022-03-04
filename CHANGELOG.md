# CHANGELOG for `exception_handling`

Inspired by [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Note: this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.10.0] - Unreleased
### Removed
- Remove custom object inspection
  This removed Honeybadger-specific callbacks (`lib/exception_handling/honeybadger_callbacks.rb`)

### Deprecated
- Deprecated use of Honeybadger fork

## [2.9.0] - 2020-03-02
### Added
- Automatically registers with the `escalate` gem's `on_escalate` callback.

## [2.8.1] - 2020-12-01
### Added
- If the `log_context` key `honeybadger_grouping:` is set, pass that value to the `controller:` keyword argument of `HoneyBadger.notify`.

## [2.8.0] - 2020-10-19
### Deprecated
- Deprecated Email Escalation Methods: `escalate_to_production_support`, `escalate_error`, `escalate_warning`, `ensure_escalation`

## [2.7.0] - 2020-10-14
### Added
- Added `LoggingMethods` as a replacement for `Methods` without setting controller or checking for long controller action.
### Deprecated
- Deprecated `Methods` in favor of `LoggingMethods`.

## [2.6.1] - 2020-10-14
### Fixed
- Fixed honeybadger_context_data to always merge `current_context_for_thread`, even if `log_context:` is passed as `nil`.

## [2.6.0] - 2020-08-26
### Changed
- Calling `log_warning` will now log with Severity::WARNING rather than FATAL.
- Reordered the logging to put the exception class next to the message.

## [2.5.0] - 2020-08-19
### Added
- The `**log_context` passed to `log_error`/`log_warning`/`log_info` is now
  passed into `Honeybadger.notify()`, in `context: { log_context: ... }`.

### Fixed
- Silenced test warning noise by no longer running ruby -w.
- Renamed a constant to ALLOWLIST.

## [2.4.4] - 2020-08-10
### Fixed
- `ExceptionHandling.logger = nil` no longer displays an "implicit extend" deprecation warning.

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

[2.9.0]: https://github.com/Invoca/exception_handling/compare/v2.8.1...v2.9.0
[2.8.1]: https://github.com/Invoca/exception_handling/compare/v2.8.0...v2.8.1
[2.8.0]: https://github.com/Invoca/exception_handling/compare/v2.7.0...v2.8.0
[2.7.0]: https://github.com/Invoca/exception_handling/compare/v2.6.1...v2.7.0
[2.6.1]: https://github.com/Invoca/exception_handling/compare/v2.6.0...v2.6.1
[2.6.0]: https://github.com/Invoca/exception_handling/compare/v2.5.0...v2.6.0
[2.5.0]: https://github.com/Invoca/exception_handling/compare/v2.4.4...v2.5.0
[2.4.4]: https://github.com/Invoca/exception_handling/compare/v2.4.3...v2.4.4
[2.4.3]: https://github.com/Invoca/exception_handling/compare/v2.4.2...v2.4.3
[2.4.2]: https://github.com/Invoca/exception_handling/compare/v2.4.1...v2.4.2
[2.4.1]: https://github.com/Invoca/exception_handling/compare/v2.4.0...v2.4.1
