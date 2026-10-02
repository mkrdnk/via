# Via

![via logo](web/docs/assets/via-logo.svg)

**Via is a small, focused HTTP reverse proxy.**

[Website](https://via.makridenko.com/) ·
[Documentation](https://via.makridenko.com/docs/)

Via is an early-stage, concurrent HTTP reverse proxy written in Crystal. It
supports host/path routing, streaming request and response bodies, keep-alive,
reusable upstream connections, transparent WebSocket tunnels, TLS termination,
and atomic configuration reloads.

## Quick start

Download the build for your distribution from
[GitHub Releases](https://github.com/mkrdnk/via/releases), then save this as
`via.yaml`:

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

```sh
via -c via.yaml
```

To build from source, install Crystal 1.21.1 or newer, Shards, and the OpenSSL
development libraries, then run:

```sh
make doctor
make release
```

See [Install and run](web/docs/getting-started.md) for release verification,
distribution-specific requirements, and HTTP-only builds.

## Documentation

- [Install and run](web/docs/getting-started.md)
- [Configuration](web/docs/configuration.md)
- [Proxying and WebSockets](web/docs/proxying.md)
- [Static files](web/docs/static-files.md)
- [TLS](web/docs/tls.md)
- [Command line](web/docs/cli.md)
- [Run as a service](web/docs/service.md)
- [Reload configuration](web/docs/hot-reload.md)
- [Logs and troubleshooting](web/docs/logging.md)

Via is under active development.

## License

Apache-2.0
