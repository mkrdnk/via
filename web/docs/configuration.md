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

Across a directory, `listen` must be declared exactly once and top-level
`proxy_pass` at most once. Route arrays from all fragments are concatenated.
The normal validation rules are applied after merging.

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
