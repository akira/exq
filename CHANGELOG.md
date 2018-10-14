# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [0.12.2] - 2018-10-14

### Fixed
- Don't assume redis_opts is enumerable by @ryansch

### Added
- Add {:system, VAR} format support for more config params by @LysanderGG
- Allow setting mode to both [:enqueuer, :api] by @buob

### Changed
- Specify less than 0.8.0 on redix version in mix.exs by @buob

## [0.12.1] - 2018-07-13

### Fixed
- Cleanup packaging for `elixir_uuid` change.

## [0.12.0] - 2018-07-12

### Fixed
- Change `uuid` to `elixir_uuid` which has been renamed. This will prevent future namespace clashes by @tzilist.

## [0.11.0] - 2018-05-12

### Added
- Trim dead jobs queue after certain size by @ananthakumaran.
- Add an api to list all subscriptions (active queues) by @robobakery.
- Have top supervisor wait for worker drainer to gracefully terminate @frahugo.

## [0.10.1] - 2018-02-11

### Fixed
- Fix retry for Sidekiq job format using retry => true by @deepfryed.

## [0.10.0] - 2018-02-11

### Fixed
- Remove Password logging by @akira.

### Added
- Redis Sentinel support by @ananthakumaran.
- Make redis module name and start_link args configurable @ananthakumaran.


