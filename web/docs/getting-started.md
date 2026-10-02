# Getting started

## Install a release

Download the archive for your distribution from
[GitHub Releases](https://github.com/mkrdnk/via/releases):

```text
via-VERSION-fedora43-x86_64.tar.gz
via-VERSION-debian13-x86_64.tar.gz
via-VERSION-ubuntu24.04-x86_64.tar.gz
```

Verify and unpack it:

```sh
sha256sum --check via-VERSION-DISTRIBUTION-x86_64.tar.gz.sha256
tar -xzf via-VERSION-DISTRIBUTION-x86_64.tar.gz
sudo install -m 0755 via-VERSION-DISTRIBUTION-x86_64/via /usr/local/bin/via
via --version
```

Release binaries include TLS support and use the target distribution's system
libraries.

## Build from source

Building requires Crystal 1.21.1 or newer and Shards. TLS builds also require
OpenSSL development files.

Fedora:

```sh
sudo dnf install openssl-devel
```

Debian or Ubuntu:

```sh
sudo apt install libssl-dev pkg-config
```

```sh
make doctor
make release
sudo install -m 0755 bin/via /usr/local/bin/via
```

Use an HTTP-only build only when TLS listeners and HTTPS upstreams are not
needed:

```sh
make release-http
```

## Create a configuration

Save the following as `via.yaml`:

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

## Run Via

```sh
via run -c via.yaml
```

Requests to `http://localhost:8080` are now proxied to
`http://localhost:3000`.

The CLI also exposes:

```sh
via check -c via.yaml
via run --debug -c via.yaml
via --help
via --version
```

Continue with [Configuration](configuration.md) to add routes, TLS, logging, or
multiple listeners. For a long-running installation, see
[Run as a service](service.md).
