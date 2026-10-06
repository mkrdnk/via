# Via

**Via is a small, focused HTTP/1.1 reverse proxy with a strict YAML
configuration.**

Via routes traffic by host and path, streams it to reusable upstream
connections, and keeps deployment and operations explicit.

## Start in a minute

After [installing Via](getting-started.md), save this as `via.yaml`:

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

## Core capabilities

- route by host and segment-aware path prefix;
- strip a matched prefix and set or remove route headers;
- stream request and response bodies and tunnel WebSockets;
- terminate TLS or serve static files and SPAs;
- run multiple listeners from one configuration directory;
- reload routes and certificates atomically;
- trace requests with structured logs and request IDs.

## Choose your next task

### Configure traffic

- [Routes, matching, prefix stripping, headers, and redirects](configuration.md)
- [HTTP forwarding, body streaming, and WebSockets](proxying.md)
- [TLS termination and certificate reload](tls.md)
- [Static sites and SPA fallback](static-files.md)

### Deploy

- [Install and run](getting-started.md)
- [Run as a systemd service](service.md)
- [Run in a container](container.md)

### Operate and troubleshoot

- [Reload configuration safely](hot-reload.md)
- [Trace failures in logs](logging.md)
- [CLI commands and flags](cli.md)

Via intentionally does not provide caching, FastCGI, WAF functionality,
scripting, plugins, arbitrary rewrite rules, ACME automation, or load
balancing.
