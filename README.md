# Via

![via logo](web/docs/assets/via-logo.svg)

**Via is a tiny HTTP reverse proxy for when you only need `proxy_pass`.**

[Website](https://via.makridenko.com/) ·
[Documentation](https://via.makridenko.com/docs/)

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

- [Getting started](web/docs/getting-started.md)
- [Configuration](web/docs/configuration.md)
- [Routing](web/docs/routing.md)
- [CLI](web/docs/cli.md)
- [Proxy behavior](web/docs/proxy-behavior.md)
- [Error pages and request IDs](web/docs/errors.md)
- [Debug mode and hot reload](web/docs/hot-reload.md)
- [TLS](web/docs/tls.md)
- [Static files](web/docs/static-files.md)
- [Architecture](web/docs/architecture.md)
- [Development and benchmarking](web/docs/development.md)

Via is under active development. WebSocket proxying, configurable headers, and
upstream timeouts are planned but not yet available.

## License

Apache-2.0
