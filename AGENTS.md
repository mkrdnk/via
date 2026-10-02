# Repository Guidelines

## Project Structure & Module Organization

Via is a concurrent HTTP reverse proxy written in Crystal. `src/via.cr` loads the library; `src/via/main.cr` is the executable entry point. Keep implementation under `src/via/`, organized by responsibility: `configuration/`, `routing/`, `proxy/`, `tls/`, `runtime/`, `http/`, `static/`, `logging/`, and `console/`.

Tests live in `spec/`, with shared helpers in `spec/spec_helper.cr`. Documentation lives in `web/docs/`; landing-page files, the MkDocs configuration, and preview configuration live in `web/`. Generated binaries and documentation go to `bin/` and `site/`.

## Build, Test, and Development Commands

Use Crystal 1.21.1 or newer, Shards, and OpenSSL development files for TLS builds. Documentation checks require MkDocs and mike (`python -m pip install mkdocs mike`).

- `make doctor`: inspect Crystal and OpenSSL availability.
- `make build` / `make release`: build development / optimized binaries.
- `make run CONFIG=via.yaml`: build and run with your YAML configuration.
- `make debug CONFIG=via.yaml`: run with debug mode enabled.
- `make test`: run Crystal specs.
- `make format`: format Crystal source; `make format-check` checks without changing files.
- `make check`: run formatting checks, specs, and the strict documentation build.
- `make check-http`: run checks without OpenSSL; `build-http` and `release-http` also support HTTP-only builds.
- `make docs-serve`: preview the website at `http://localhost:8000/`.
- `make pages-smoke`: build and verify the website through Via.

## Coding Style & Naming Conventions

Follow `.editorconfig`: two-space indentation, UTF-8, LF endings, a final newline, and no trailing whitespace in Crystal files. Use `snake_case` for files and methods and `PascalCase` for types. Preserve explicit namespaces such as `Via::Routing`; keep production module boundaries distinct from convenience aliases in specs. Run `make format` before submitting code.

## Testing Guidelines

Use Crystal's built-in `spec` framework, `*_spec.cr` filenames, and descriptive `describe` / `it` blocks. Reuse temporary-directory and server helpers for cleanup and ephemeral ports. Run a focused file with `crystal spec spec/banner_spec.cr`. Add regression coverage for behavior changes and check both TLS and HTTP-only paths when relevant. No numeric coverage threshold is configured.

## Commit & Pull Request Guidelines

Recent history favors short, prefixed subjects such as `feat: add structured operational logging` and `docs: improve code block contrast`. Follow that style and keep commits focused.

PRs should explain the problem, resulting behavior, and validation performed; link related issues when available. Update `web/docs/` for user-visible changes and include screenshots for website appearance changes.
