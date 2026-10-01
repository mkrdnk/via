# Via

![via logo](docs/assets/via-logo.svg)

**Via is a tiny HTTP reverse proxy for when you only need `proxy_pass`.**

Via is an early-stage, concurrent HTTP reverse proxy written in Crystal. It
supports host/path routing, streaming request and response bodies, keep-alive,
reusable upstream connections, TLS termination, and atomic configuration
reloads.

## Quick start

Via requires Crystal 1.21.1 or newer and OpenSSL development files:

```sh
# Fedora
sudo dnf install openssl-devel

# Debian/Ubuntu
sudo apt install libssl-dev pkg-config
```

```sh
make doctor
make release
```

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

```sh
bin/via -c via.yaml
```

For an HTTP-only build without OpenSSL development files:

```sh
make release-http
```

## Documentation

- [Getting started](docs/getting-started.md)
- [Configuration and routing](docs/configuration.md)
- [Proxy behavior](docs/proxy-behavior.md)
- [Error pages and request IDs](docs/errors.md)
- [Debug mode and hot reload](docs/hot-reload.md)
- [TLS](docs/tls.md)
- [Static files](docs/static-files.md)
- [Architecture](docs/architecture.md)
- [Development and benchmarking](docs/development.md)

Via is under active development. WebSocket proxying, configurable headers, and
upstream timeouts are planned but not yet available.

## License

Apache-2.0
