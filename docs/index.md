# Via

**Via is a tiny HTTP reverse proxy for when you only need `proxy_pass`.**

Via is a concurrent HTTP reverse proxy written in Crystal. Its current
development milestone provides:

- HTTP/1.1 reverse proxying;
- host and path routing;
- streaming request and response bodies;
- downstream and upstream keep-alive;
- reusable upstream connections;
- atomic hot reload for file and directory configurations;
- manual TLS termination with certificate reload;
- debug diagnostics for invalid configuration;
- strict YAML configuration and validation;
- built-in gateway error pages with request IDs.

Via deliberately stays focused. It does not currently provide caching,
FastCGI, WAF functionality, scripting, plugins, complex rewrite rules, or
advanced load-balancing algorithms.

## Current status

Via is under active development and is not yet a stable production release.
Static files, WebSocket proxying, configurable headers, and upstream timeouts
remain on the roadmap.

Start with [Getting started](getting-started.md), then see
[Configuration and routing](configuration.md) for route matching behavior and
[Proxy behavior](proxy-behavior.md) for forwarding semantics. See
[Error pages and request IDs](errors.md) for failure behavior and
[Debug mode and hot reload](hot-reload.md) for the configuration workflow.
