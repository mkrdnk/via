# Via

**Via is a tiny HTTP reverse proxy for when you only need `proxy_pass`.**

Via is a concurrent HTTP reverse proxy written in Crystal. Its current
development milestone provides:

- HTTP/1.1 reverse proxying;
- host and path routing;
- streaming request and response bodies;
- downstream and upstream keep-alive;
- reusable upstream connections;
- strict YAML configuration and validation;
- built-in `404 Not Found` and `502 Bad Gateway` responses.

Via deliberately stays focused. It does not currently provide caching,
FastCGI, WAF functionality, scripting, plugins, complex rewrite rules, or
advanced load-balancing algorithms.

## Current status

Via is under active development and is not yet a stable production release.
TLS termination, hot reload, static files, WebSocket proxying, configurable
headers, and upstream timeouts remain on the roadmap.

Start with [Getting started](getting-started.md), then see
[Configuration and routing](configuration.md) for route matching behavior and
[Proxy behavior](proxy-behavior.md) for forwarding semantics.
