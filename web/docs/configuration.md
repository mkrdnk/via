# Configuration

Via reads a strict YAML configuration. Unknown fields and invalid values cause
startup to fail with a configuration error.

## Disabling a configuration

Configurations are enabled by default. Set `enable: false` at the top level to
skip a file without deleting or renaming it:

```yaml
enable: false
listen: ":80"
proxy_pass: http://localhost:3000
```

Via parses the file as strict YAML, then excludes it before listener and route
validation. This means a disabled file does not need a complete `listen` or
route configuration, although its fields must still use valid YAML types and
known names.

When `-c` points to a directory, disabled files are left out before fragments
are grouped and merged. Other enabled listeners and fragments continue to run.
If every file is disabled, `via run` exits successfully without binding a
listener, and `via check` reports the configuration as valid with no enabled
listeners.

## Single upstream

The smallest configuration sends every request to one upstream:

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

`listen` accepts:

- `:PORT` to listen on all IPv4 interfaces;
- `HOST:PORT`;
- `[IPv6]:PORT`.

`proxy_pass` accepts an HTTP or HTTPS URL without a path, query, fragment, or
credentials. For compatibility, an unquoted integer from `200` through `599`
still returns that status directly, but new configurations should use
[`return`](#immediate-responses-and-redirects).

The short form may include `host`. This limits the route to that request host:

```yaml
listen: ":80"
host: example.com
proxy_pass: https://$host
```

`$host` in `proxy_pass` is replaced with the configured `host` during
validation. It is rejected when the route has no `host`, so request input can
never select an arbitrary upstream.

## Upstream timeouts

Set connection, read, and write timeouts for proxied upstream requests:

```yaml
listen: ":443"
timeouts:
  connect: 5s
  read: 30s
  write: 30s

routes:
  - path: /
    proxy_pass: http://localhost:3000
    timeouts:
      connect: 10s
```

Top-level values apply to every proxy route. A route-level `timeouts` block
overrides only the fields it contains, so this example uses a 10-second connect
timeout and inherits the 30-second read and write timeouts.

Durations must be positive and use `ms`, `s`, `m`, or `h`; decimal values such
as `1.5s` are accepted. Omitted fields keep Crystal's default of no timeout.
Timeouts cover HTTP traffic and WebSocket connections. A timeout before the
downstream response starts returns `504 Gateway Timeout`.

## Graceful shutdown

Graceful shutdown is enabled by default and needs no configuration. On
`SIGINT` or `SIGTERM`, Via stops accepting connections, waits for active HTTP
requests, gives upgraded WebSocket connections five seconds to finish, closes
the remaining WebSockets and upstream connection pools, and exits.

To change only the WebSocket grace period for a listener:

```yaml
listen: ":8080"
shutdown:
  websocket_timeout: 8s
proxy_pass: http://localhost:3000
```

`websocket_timeout` accepts the same positive duration syntax as upstream
timeouts. The default five-second grace period fits within Docker's default
ten-second stop timeout. Active HTTP requests are allowed to finish before this
period starts, so configure the orchestrator's total stop timeout accordingly.

## Logging

Operational logs go to stderr at `INFO` level by default. Set `log_file` to
append them to a file and `log_level` to change the minimum severity:

```yaml
listen: ":8000"
log_file: /var/log/via.log
log_level: INFO
proxy_pass: http://localhost:3000
```

Supported levels are `DEBUG`, `INFO`, `WARN`, and `ERROR`. See
[Logs and troubleshooting](logging.md) for output, overrides, and request IDs.

To enable diagnostics and verbose proxy logs for only this listener, set
`debug: true`:

```yaml
listen: ":8000"
debug: true
proxy_pass: http://localhost:3000
```

This selects the `DEBUG` log level and shows configuration errors in the browser
when Via can keep the listener running. In a directory with multiple listeners,
other listeners remain in production mode.

## Routes

Use `routes` to select different upstreams by host and path:

```yaml
listen: ":8080"

routes:
  - host: api.example.com
    path: /api
    proxy_pass: http://localhost:8000
    strip_prefix: true

  - path: /
    proxy_pass: http://localhost:3000

  - path: /admin
    return: 403
```

Top-level `proxy_pass` and `routes` are mutually exclusive. Every route must
have exactly one target: `proxy_pass`, `static`, or `return`. `host` is optional
and `path` defaults to `/`.

### Header manipulation

Proxy routes can set or remove request and response headers:

```yaml
routes:
  - host: api.example.com
    proxy_pass: http://localhost:8000

    headers:
      request:
        set:
          X-Service: api
        remove:
          - X-Powered-By

      response:
        set:
          X-Frame-Options: DENY
        remove:
          - X-Upstream-Only
```

`request` rules modify the headers sent to the upstream. `response` rules
modify the headers returned to the client, including WebSocket handshake
responses. Under either direction:

- `set` maps a header name to one value, replacing any existing values;
- `remove` lists headers to delete;
- names are case-insensitive;
- a header cannot appear in both `set` and `remove`.

Header rules are only valid on routes whose `proxy_pass` is an HTTP or HTTPS
URL. Via rejects invalid names and values. It also protects headers whose
modification would conflict with HTTP framing or Via's forwarding policy:

- hop-by-hop headers (`Connection`, `Keep-Alive`, `Proxy-Authenticate`,
  `Proxy-Authorization`, `TE`, `Trailer`, `Transfer-Encoding`, and `Upgrade`);
- `Content-Length` and `X-Request-ID`;
- on requests, `Host`, `X-Forwarded-For`, `X-Forwarded-Host`, and
  `X-Forwarded-Proto`;
- on responses, `Server`.

### Immediate responses and redirects

Use `return` to respond without contacting an upstream:

```yaml
listen: ":80"

routes:
  - path: /admin
    return: 403

  - host: example.com
    path: /
    return: 301 https://$host$query
```

`return` accepts an unquoted integer from `200` through `599`. Via renders its
built-in status page with a request ID. Statuses that prohibit response content
(`204`, `205`, and `304`) remain empty.

To redirect, use `STATUS LOCATION`. Redirect locations are supported for `301`,
`302`, `303`, `307`, and `308`; they may be absolute URLs or relative
references. Redirect responses have an empty body. Locations support:

- `$host`, replaced during validation with the route's configured `host`;
- `$query`, replaced for each request with `?` and the original encoded query
  string, or with an empty string when the request has no query.

A location containing `$host` requires the route to declare `host`. This keeps
an arbitrary request `Host` from selecting the redirect destination. Other
variables are rejected.

### Path matching

Paths use segment-aware prefix matching:

- `/api` matches `/api` and `/api/users`;
- `/api` does not match `/apix`.

The longest matching path wins. A trailing slash in a configured path is
normalized away, so `/api/` and `/api` describe the same route.

Proxy routes forward the original path and query unchanged by default. Set
`strip_prefix: true` on a route with an upstream URL to remove its matched path
before forwarding:

```yaml
routes:
  - path: /api
    proxy_pass: http://localhost:8000
    strip_prefix: true
```

This forwards `/api/users?active=true` as `/users?active=true`. A request for
the route path itself (`/api`) is forwarded as `/`. On a `/` route,
`strip_prefix` has no effect. Static routes always remove their matched prefix
when resolving a file.

### Host matching

Host matching is exact and case-insensitive. The port in the incoming `Host`
header is ignored. For routes with equal paths, a matching host-specific route
takes precedence over a route without `host`. A route without `host` is the
fallback for any hostname.

Duplicate normalized host/path pairs are rejected. If no route matches, Via
responds with `404 Not Found`.

## Configuration directories

`-c` accepts either one YAML file or a directory containing `.yaml` and `.yml`
fragments. Files are merged in lexical filename order:

```text
/etc/via/config/
├── 00-server.yaml
├── 10-api.yaml
└── 20-app.yaml
```

`00-server.yaml`:

```yaml
listen: ":8080"
```

`10-api.yaml`:

```yaml
routes:
  - host: api.example.com
    path: /
    proxy_pass: http://localhost:8000
```

`20-app.yaml`:

```yaml
routes:
  - path: /
    proxy_pass: http://localhost:3000
```

When a directory contains one `listen` value, all files remain fragments of
that listener: `listen` may be repeated, files without it are accepted, and
route arrays are concatenated.

A directory may also define multiple listeners. In that mode every YAML file
must declare `listen`; files with the same value are merged into one listener,
while distinct values run concurrently with independent routes and TLS:

```text
/etc/via/config/
├── 10-http.yaml
└── 20-https.yaml
```

`10-http.yaml`:

```yaml
listen: ":80"
host: example.com
proxy_pass: https://$host
```

`20-https.yaml`:

```yaml
listen: ":443"
tls:
  cert: /etc/via/cert.pem
  key: /etc/via/key.pem
proxy_pass: http://localhost:3000
```

Within each listener, `host`, `debug`, `log_file`, `log_level`, top-level
`proxy_pass`, `timeouts`, `shutdown`, and `tls` may each be declared at most
once. The normal validation rules are applied after merging. A file without
`listen` is rejected when multiple listeners exist because Via cannot determine
which listener should receive it. Files with `enable: false` are ignored before
these rules are applied.

See [Reload configuration](hot-reload.md) for reload behavior.

## TLS

Add a certificate and private key to terminate TLS:

```yaml
listen: ":443"

tls:
  cert: /etc/via/cert.pem
  key: /etc/via/key.pem

proxy_pass: http://localhost:8000
```

Both files must exist and be readable. See [TLS](tls.md) for runtime and reload
behavior.

## Static routes

A route may serve a directory instead of proxying:

```yaml
routes:
  - path: /api
    proxy_pass: http://localhost:8000

  - path: /
    static: ./dist
```

For SPA fallback behavior, use the object form:

```yaml
routes:
  - path: /
    static:
      root: ./dist
      fallback: index.html
```

Each route must contain exactly one of `proxy_pass`, `static`, or `return`. See
[Static files](static-files.md) for path mapping, caching, range requests, and
security behavior.
