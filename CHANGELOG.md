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

## 0.2.0 - [unreleased]

### Added

- Numeric `proxy_pass` targets from `200` through `599` for routes that return
  a fixed HTTP status without contacting an upstream.
- Built-in HTML status pages, including a dedicated `403 Forbidden` page, for
  fixed response routes.
- `log_file` and `log_level` configuration options with append-mode file
  output, severity filtering, and hot reload support.
- `--log-level` CLI override with support for `DEBUG`, `INFO`, `WARN`, and
  `ERROR`.

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
