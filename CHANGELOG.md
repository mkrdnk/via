# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
## VERSION - [unreleased]

### Added

### Changed

### Removed

### Fixed
-->

## VERSION - [unreleased]

### Added

- Route-level request and response header `set` and `remove` rules for HTTP and
  WebSocket proxying.
- Optional route-level `strip_prefix` rewriting for HTTP and WebSocket upstream
  requests.
- Route-level `return` directives for immediate status responses and redirects,
  with safe `$host` and request-time `$query` expansion.
- Configurable upstream connect, read, and write timeouts with listener defaults
  and per-route overrides for HTTP and WebSocket proxying.
- Graceful `SIGINT` and `SIGTERM` shutdown that drains active HTTP requests,
  gives WebSockets a configurable grace period, and then closes upstream pools.

## 0.3.1 - 2026-10-04

### Changed

- The packaged systemd service can read root-managed TLS certificates, including
  Certbot's default paths, while continuing to run as the unprivileged `via`
  user. Inaccessible TLS files now produce a configuration error instead of an
  unhandled exception.

### Fixed

- Removed the process-wide `CAP_DAC_READ_SEARCH` permission added to the
  packaged service in 0.3.1. TLS files must now be explicitly readable by the
  `via` account, preventing TLS access from also bypassing static-file
  permissions.

---

## 0.3.0 - 2026-10-04

### Added

- Transparent WebSocket proxying over HTTP and HTTPS upstreams, including
  subprotocols, extensions, bidirectional frame relay, and ordinary HTTP
  rejection responses.
- `via check` command for validating a configuration without starting listeners.
- Per-listener debug mode through `debug: true` in YAML configuration.
- Native DEB and RPM release packages with checksums, an example configuration
  and welcome page, and automatic systemd service setup.
- A one-line installer for supported Linux distributions that selects and
  verifies the matching package from the latest GitHub release.
- A small multi-stage Alpine image for running Via as an unprivileged container,
  with automated x86-64 and ARM64 publication to GitHub Container Registry.

### Changed

- Restructured the documentation around installation, configuration, proxying,
  and operations; removed maintainer-only architecture, development, release,
  and website deployment pages from the user guide.
- Release assets now use distribution-independent Linux names and are published
  as RPM, DEB, and `.tar.xz` binary packages for x86-64 and ARM64.
- Proxy startup now uses `via run`; both `run` and `check` load `/etc/via/` by
  default and accept `-c`/`--config` overrides.

---

## 0.2.0 - 2026-10-02

### Added

- Numeric `proxy_pass` targets from `200` through `599` for routes that return
  a fixed HTTP status without contacting an upstream.
- Built-in HTML status pages, including a dedicated `403 Forbidden` page, for
  fixed response routes.
- `log_file` and `log_level` configuration options with append-mode file
  output, severity filtering, and hot reload support.
- `--log-level` CLI override with support for `DEBUG`, `INFO`, `WARN`, and
  `ERROR`.
- Multiple independent HTTP and TLS listeners in configuration directories.
- Top-level `host` routing for the short `proxy_pass` form, including safe
  `$host` substitution from the configured route host.
- `config_file` context on every operational log record.

### Changed

- Startup summaries now show fixed response targets and the effective logging
  destination and level.
- `--log-level` takes precedence over `--debug`, which takes precedence over
  `log_level` from YAML.

---

## 0.1.1 - 2026-10-01

### Added
- Console logs

---

## 0.1.0 - 2026-10-01
- Public release!
