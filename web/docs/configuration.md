# Configuration

Via reads a strict YAML configuration. Unknown fields and invalid values cause
startup to fail with a configuration error.

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

`proxy_pass` accepts either:

- an HTTP or HTTPS URL without a path, query, fragment, or credentials; or
- an unquoted integer from `200` through `599`, which returns that status
  directly without contacting an upstream.

The short form may include `host`. This limits the route to that request host:

```yaml
listen: ":80"
host: example.com
proxy_pass: https://$host
```

`$host` in `proxy_pass` is replaced with the configured `host` during
validation. It is rejected when the route has no `host`, so request input can
never select an arbitrary upstream.

## Logging

Operational logs go to standard error at `INFO` level by default. Set
`log_file` to append them to a file and `log_level` to control the minimum
recorded level:

```yaml
listen: ":8000"
log_file: /var/log/via.log
log_level: INFO
proxy_pass: http://localhost:3000
```

Supported levels are `DEBUG`, `INFO`, `WARN`, and `ERROR`, matched
case-insensitively. `WARNING` is accepted as an alias for `WARN`. Relative log
paths are resolved from Via's working directory. The parent directory must
already exist and be writable.

Via reopens the configured file and applies level changes during hot reload. If
the new file cannot be opened, the replacement configuration is rejected and
logging continues to the previous destination. The `--log-level` CLI option
overrides this setting. Without that explicit override, `--debug` sets the
effective level to `DEBUG`.

## Routes

Use `routes` to select different upstreams by host and path:

```yaml
listen: ":8080"

routes:
  - host: api.example.com
    path: /api
    proxy_pass: http://localhost:8000

  - path: /
    proxy_pass: http://localhost:3000

  - path: /admin
    proxy_pass: 403
```

Top-level `proxy_pass` and `routes` are mutually exclusive. Every route must
have exactly one target: `proxy_pass` or `static`. `host` is optional and
`path` defaults to `/`. A numeric `proxy_pass` renders Via's built-in status
page with a request ID. Statuses that prohibit response content (`204`, `205`,
and `304`) remain empty.

See [Routing](routing.md) for host matching, path matching, and precedence.

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

Within each listener, `host`, `log_file`, `log_level`, top-level `proxy_pass`,
and `tls` may each be declared at most once. The normal validation rules are
applied after merging. A file without `listen` is rejected when multiple
listeners exist because Via cannot determine which listener should receive it.

See [Debug mode and hot reload](hot-reload.md) for reload behavior.

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

Each route must contain exactly one of `proxy_pass` or `static`. See
[Static files](static-files.md) for path mapping, caching, range requests, and
security behavior.
