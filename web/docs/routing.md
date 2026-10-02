# Routing

Routes select a proxy or static target by request host and path:

```yaml
listen: ":8080"

routes:
  - host: api.example.com
    path: /api
    proxy_pass: http://localhost:8000

  - path: /
    proxy_pass: http://localhost:3000
```

## Path matching

Paths use segment-aware prefix matching:

- `/api` matches `/api`;
- `/api` matches `/api/users`;
- `/api` does not match `/apix`.

The longest matching path wins. A trailing slash in a configured path is
normalized away, so `/api/` and `/api` describe the same route.

Proxy routes forward the original request path and query unchanged. Matching
`/api` does not strip `/api` from the upstream request. Static routes remove
their matched prefix when resolving a file.

## Host matching

Host matching is exact and case-insensitive. Via ignores the port in the
incoming `Host` header.

For routes with equal paths, a matching host-specific route takes precedence
over a route without `host`. A route without `host` acts as a fallback for any
hostname.

Configurations containing duplicate normalized host/path pairs are rejected.
If no route matches, Via responds with `404 Not Found`.

## Targets

Every route has exactly one target:

```yaml
routes:
  - path: /api
    proxy_pass: http://localhost:8000

  - path: /
    static: ./dist
```

See [Proxy behavior](proxy-behavior.md) and
[Static files](static-files.md) for target-specific behavior.
