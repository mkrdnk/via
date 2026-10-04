# Getting started

## Install a release

Download the package for your distribution from
[GitHub Releases](https://github.com/mkrdnk/via/releases):

```text
via-VERSION-linux-x86_64.rpm
via-VERSION-linux-x86_64.deb
via-VERSION-linux-aarch64.rpm
via-VERSION-linux-aarch64.deb
```

Choose the package matching your architecture, verify it, and install it:

```sh
sha256sum --check PACKAGE.sha256

# Fedora / RHEL
sudo dnf install ./via-VERSION-linux-x86_64.rpm

# Debian / Ubuntu
sudo apt install ./via-VERSION-linux-x86_64.deb

via --version
```

On a running systemd system, installing a native package also enables and
starts `via.service`. The initial service listens on port 80 in debug mode and
serves a local welcome page. Before using the service in production, edit
`/etc/via/example-config.yaml` and remove `debug: true`.

Tar archives remain available for installations that do not use an OS package:

```text
via-VERSION-linux-x86_64-bin.tar.xz
via-VERSION-linux-aarch64-bin.tar.xz
```

Choose the archive matching your architecture, verify it, and unpack it:

```sh
sha256sum --check via-VERSION-linux-x86_64-bin.tar.xz.sha256
tar -xJf via-VERSION-linux-x86_64-bin.tar.xz
sudo install -m 0755 via-VERSION-linux-x86_64-bin/via /usr/local/bin/via
via --version
```

Release binaries are available for x86-64 and ARM64. They include TLS support
and use Linux system libraries.

## Build from source

Building requires Crystal 1.21.1 or newer and Shards. TLS builds also require
OpenSSL development files.

Fedora / RHEL:

```sh
sudo dnf install openssl-devel
```

Debian / Ubuntu:

```sh
sudo apt install libssl-dev pkg-config
```

```sh
make doctor
make release
sudo install -m 0755 bin/via /usr/local/bin/via
```

To create a native package for the current distribution, run one of:

```sh
make package-bin
make package-deb
make package-rpm
```

Each target builds the release binary and writes the package and its `.sha256`
file to `dist/`. Creating the binary archive requires `xz`. The first DEB or RPM
build downloads a pinned, checksum-verified
[nFPM](https://nfpm.goreleaser.com/) binary to `.tools/`; set `NFPM` to use an
existing executable instead.

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
