# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/).

## [Unreleased]


## [0.16.1] - 2021-12-13

### Added

### Changed

### Fixed
- Fix @doc redefined warnings #463 by deepfryed

## [0.16.0] - 2021-12-12

NOTE: Please read PR #458 for upgrade instructions.

### Added
- Add retried_at field for Sidekiq compatibility #450 by @ananthakumaran
- Add apis to support exq_ui #452 by @ananthakumaran
- Add documentation about mode: :enqueuer and Exq.Enqueuer.queue_in #456 by @dbernheisel
- Add api to immediately enqeueue jobs from retry/scheduled queue #461 by @ananthakumaran
- Add api to re-enqueue dead job #462 by @ananthakumaran

### Changed
- Add Sidekiq 5 compatibility #458 by @ananthakumaran
- Use latest Phoenix child spec style #459 by @vovayartsev
- Replace deprecated supervisor calls #453 by @vkuznetsov

### Fixed
- Handle timeouts on middleware pipeline #444 by @ananthakumaran
- Use the correct scheduled time for enqueued_at field for mock #449 by @ananthakumaran


## [0.15.0] - 2021-07-19

### Added
- Add dequeue behavior for ability to implement things like concurrency control #421 by @ananthakumaran
- Api Module Documentation #440 by @kevin-j-m

### Changed
- Use Lua script to schedule job for better performance and memory leak fix #427 by @ananthakumaran
- Logging fixes #429 by @rraub
- Relax poison dependency #431 by @ananthakumaran
- Use github actions instead of Travis #433 by @ananthakumaran
- Use the same same module conversion logic in mock as well #434 by @ananthakumaran
- use Task instead of spawn_link for starting workers #436 by @mitchellhenke

### Fixed
- re-enqueue unfinished jobs to the beginning of queue on restart #424 by @ananthakumaran
- Fix for sentinel 0.11.0+ #428 by @ananthakumaran
- Fixes for generated HTML docs by #442 @kianmeng


## [0.14.0] - 2020-08-08

### Added
- Node heartbeat functionality for dynamic environments #392 by @ananthakumaran (disabled by default).
- Exq telemetry events #414 by @hez
- Allow custom job IDs #417 by @bradediger

### Changed
- Don't log Redis disconnects #420 by @isaacsanders

### Fixed
- exq.run mix task starts dependent apps as well #408 by @ananthakumaran
- Cast queue level concurrency #401 by @ananthakumaran
- Fix documentation typo #423 by @LionsHead
- Fix conflicting unit in docs #419 by @JamesFerguson

## [0.13.5] - 2020-01-01

### Added
- Queue adapter for mock testing @ananthakumaran and @samidarko

## [0.13.4] - 2019-11-03

### Fixed
- Remove unnecessary serialization of enqueue calls #390 by @ananthakumaran and @sb8244
- Fix warnings by @hkrutzer #394
- Start all the apps during test by @ananthakumaran #391
- Replace KEYS with a cursored call to SCAN for realtime stats by @neslinesli93 #384

## [0.13.3] - 2019-06-16

### Added
- Handle AWS Elasticache Redis DNS failover. This ensures persistent connections are shutdown, forcing a reconnect in scenarios where a Redis node in a HA cluster is switched to READONLY mode by @deepfryed.

## [0.13.2] - 2019-03-15

### Fixed
- Fix json_library issue #369 needing addition to config file. Add default value.

## [0.13.1] - 2019-02-24

### Added
- Support for configurable JSON parser, with Jason as default by @chulkilee.

### Fixed
- Remove redundant time output for worker log by @akira.
- Fix deprecated time warning by @gvl.

## [0.13.0] - 2019-01-21

### Removed
- Due to library dependencies, support for Elixir 1.3, Elixir 1.4 and OTP 18.0, OTP 19.0 has been removed.
- Redix version older than 0.8.1 is no longer supported.
- Config options `reconnect_on_sleep` and `redis_timeout` are now removed.

### Added
- Support for Redix >= 0.8.1 by @ryansch and @ananthakumaran.
- Configuration for Mix Format by @chulkilee.
- Use :microsecond vs :microseconds by @KalvinHom.

### Changed
- Redis options are now passed in via `redis_options` by @ryansch and @ananthakumaran.
- Removed redix_sentinel dependency, now supported by new Redix version by @ananthakumaran.

## [0.12.2] - 2018-10-14

### Fixed
- Don't assume redis_opts is enumerable by @ryansch.

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
