# Configuration and routing

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

`proxy_pass` must be an HTTP or HTTPS URL without a path, query, fragment, or
credentials.

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
```

Top-level `proxy_pass` and `routes` are mutually exclusive. A route must have a
`proxy_pass`; `host` is optional and `path` defaults to `/`.

## Path matching

Route paths use segment-aware prefix matching:

- `/api` matches `/api`;
- `/api` matches `/api/users`;
- `/api` does not match `/apix`.

The longest matching path wins. A trailing slash in a configured path is
normalized away, so `/api/` and `/api` describe the same route.

Via forwards the original request path and query unchanged. Matching `/api`
does not strip `/api` from the upstream request.

## Host matching

Host matching is exact and case-insensitive. The port in the incoming `Host`
header is ignored.

For routes with the same path, a matching host-specific route takes precedence
over a route without `host`. A route without `host` can act as a fallback for
any hostname.

Configurations containing duplicate normalized host/path pairs are rejected.
If no route matches a request, Via responds with `404 Not Found`.
