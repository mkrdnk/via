# Via

![via logo](web/docs/assets/via-logo.svg)

**Via is a small, focused HTTP/1.1 reverse proxy with a strict YAML
configuration.**

[Website](https://via.makridenko.com/) ·
[Documentation](https://via.makridenko.com/docs/) ·
[Releases](https://github.com/mkrdnk/via/releases)

Via is designed for straightforward self-hosted deployments where predictable
routing and a small operational surface matter more than a plugin ecosystem.
It is early-stage software.

## What Via handles

- host- and path-based routing with longest-prefix matching;
- optional path-prefix stripping and per-route header rules;
- streaming request and response bodies over reusable upstream connections;
- transparent WebSocket tunnels;
- TLS termination and static file serving;
- multiple listeners and atomic configuration reloads;
- structured request logs, request IDs, timeouts, and graceful shutdown.

## Quick start

Install a verified package or binary from
[GitHub Releases](https://github.com/mkrdnk/via/releases). The
[installation guide](web/docs/getting-started.md) has commands for Debian,
Fedora, Ubuntu, x86-64, and ARM64.

For a quick installer-based setup:

```sh
curl -fsSL https://via.makridenko.com/install.sh | sh
```

Save this as `via.yaml`:

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

```sh
via check -c via.yaml
via run -c via.yaml
```

Requests to `http://localhost:8080` now reach
`http://localhost:3000`.

## Route an API and an application

```yaml
listen: ":8080"

routes:
  - path: /api
    proxy_pass: http://localhost:8000
    strip_prefix: true

  - path: /
    proxy_pass: http://localhost:3000
```

This sends `/api/users` to the API as `/users` and all other paths to the
application. See [Configuration](web/docs/configuration.md) for matching,
headers, redirects, static routes, TLS, and multiple listeners.

## Find the right guide

| Goal | Guide |
| --- | --- |
| Install Via and proxy the first request | [Install and run](web/docs/getting-started.md) |
| Configure routes, prefix stripping, headers, or redirects | [Configuration](web/docs/configuration.md) |
| Understand forwarding, streaming, and WebSockets | [Proxying and WebSockets](web/docs/proxying.md) |
| Terminate HTTPS | [TLS](web/docs/tls.md) |
| Serve a site or SPA | [Static files](web/docs/static-files.md) |
| Run under systemd | [Run as a service](web/docs/service.md) |
| Run an unprivileged container | [Run in a container](web/docs/container.md) |
| Reload safely or rotate certificates | [Reload configuration](web/docs/hot-reload.md) |
| Diagnose a failed request | [Logs and troubleshooting](web/docs/logging.md) |
| Look up commands and flags | [CLI reference](web/docs/cli.md) |

## Scope

Via intentionally does not provide caching, FastCGI, WAF functionality,
scripting, plugins, arbitrary rewrite rules, ACME automation, or load
balancing. See the feature-specific guides for current limitations.

## License

Apache-2.0
