# Via

**Via is a tiny HTTP reverse proxy for when you only need `proxy_pass`.**

Via is an early-stage, concurrent HTTP reverse proxy written in Crystal. It
supports host/path routing, streaming request and response bodies, keep-alive,
reusable upstream connections, and atomic configuration reloads.

## Quick start

```sh
shards build --release
```

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

```sh
bin/via -c via.yaml
```

## Documentation

- [Getting started](docs/getting-started.md)
- [Configuration and routing](docs/configuration.md)
- [Proxy behavior](docs/proxy-behavior.md)
- [Error pages and request IDs](docs/errors.md)
- [Debug mode and hot reload](docs/hot-reload.md)
- [Architecture](docs/architecture.md)
- [Development and benchmarking](docs/development.md)

Via is under active development. TLS termination, static files, WebSocket
proxying, configurable headers, and upstream timeouts are planned but not yet
available.

## License

Apache-2.0
