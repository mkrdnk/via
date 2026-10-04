# Via

![via logo](web/docs/assets/via-logo.svg)

**Via is a small, focused HTTP reverse proxy.**

[Website](https://via.makridenko.com/) ·
[Documentation](https://via.makridenko.com/docs/)

Via is an early-stage HTTP reverse proxy. It supports host/path routing,
streaming request and response bodies, keep-alive, reusable upstream
connections, transparent WebSocket tunnels, TLS termination, and atomic
configuration reloads.

## Quick start

Download the package for Debian 13 or Fedora 43, or the archive for Ubuntu
24.04, from [GitHub Releases](https://github.com/mkrdnk/via/releases). See
[Install and run](web/docs/getting-started.md) for package names, checksum
verification, and installation commands.

As a fallback when manual installation is not suitable, use the installer:

```sh
curl -fsSL https://via.makridenko.com/install.sh | sh
```

Save this as `via.yaml`:

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

```sh
via run -c via.yaml
```

To run Via as an unprivileged container:

```sh
mkdir -p config
cat > config/via.yaml <<'YAML'
listen: ":8080"
proxy_pass: http://host.docker.internal:3000
YAML
docker run --rm --publish 8080:8080 \
  --add-host host.docker.internal:host-gateway \
  --mount type=bind,source="$(pwd)/config",target=/etc/via,readonly \
  ghcr.io/mkrdnk/via:latest
```

See [Run in a container](web/docs/container.md) for configuration mounts,
upstream networking, image versions, and log access.

## Documentation

- [Install and run](web/docs/getting-started.md)
- [Configuration](web/docs/configuration.md)
- [Proxying and WebSockets](web/docs/proxying.md)
- [Static files](web/docs/static-files.md)
- [TLS](web/docs/tls.md)
- [Command line](web/docs/cli.md)
- [Run in a container](web/docs/container.md)
- [Run as a service](web/docs/service.md)
- [Reload configuration](web/docs/hot-reload.md)
- [Logs and troubleshooting](web/docs/logging.md)

## License

Apache-2.0
