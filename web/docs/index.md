# Via

**Via is a small, focused HTTP reverse proxy.**

Via accepts HTTP/1.1 traffic and sends it to an upstream selected by host and
path. It can also terminate TLS, proxy WebSockets, and serve static files.

Start with one YAML file:

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

```sh
via run -c via.yaml
```

Requests to `http://localhost:8080` now reach
`http://localhost:3000`.

## Where to go next

- [Install and run Via](getting-started.md)
- [Configure listeners, routes, and matching](configuration.md)
- [Proxy HTTP and WebSockets](proxying.md)
- [Enable TLS](tls.md)
- [Run Via as a service](service.md)
- [Use logs to diagnose failures](logging.md)

Via intentionally does not provide caching, FastCGI, WAF functionality,
scripting, plugins, rewrite rules, or load balancing.
