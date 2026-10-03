# Getting started

## Install a release

Download the package for your distribution from
[GitHub Releases](https://github.com/mkrdnk/via/releases):

```text
via-VERSION-1.fedora43.x86_64.rpm
via_VERSION_debian13_amd64.deb
via_VERSION_ubuntu24.04_amd64.deb
```

Verify and install the native package:

```sh
sha256sum --check PACKAGE.sha256

# Fedora
sudo dnf install ./via-VERSION-1.fedora43.x86_64.rpm

# Debian
sudo apt install ./via_VERSION_debian13_amd64.deb

# Ubuntu
sudo apt install ./via_VERSION_ubuntu24.04_amd64.deb

via --version
```

On a running systemd system, installing a native package also enables and
starts `via.service`. The initial service listens on port 80 in debug mode and
serves a local welcome page. Before using the service in production, edit
`/etc/via/example-config.yaml` and remove `debug: true`.

Tar archives remain available for installations that do not use an OS package:

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

To create a native package for the current distribution, run one of:

```sh
make package-deb
make package-rpm
```

Each target builds the release binary and writes the package and its
`.sha256` file to `dist/`. The first run downloads a pinned, checksum-verified
[nFPM](https://nfpm.goreleaser.com/) binary to `.tools/`; set `NFPM` to use an
existing executable instead. Build DEB packages on Debian or Ubuntu and RPM
packages on Fedora so the binary links against the target distribution's
libraries.

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
