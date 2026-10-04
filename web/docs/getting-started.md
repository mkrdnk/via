# Getting started

## Install a release

Download the file for your system and its matching `.sha256` file from
[GitHub Releases](https://github.com/mkrdnk/via/releases):

```text
via-VERSION-linux-x86_64.deb
via-VERSION-linux-aarch64.deb
via-VERSION-linux-x86_64.rpm
via-VERSION-linux-aarch64.rpm
via-VERSION-linux-x86_64-bin.tar.xz
via-VERSION-linux-aarch64-bin.tar.xz
```

Use the DEB package on Debian 13:

```sh
sha256sum --check via-VERSION-linux-x86_64.deb.sha256
sudo apt install ./via-VERSION-linux-x86_64.deb
```

Use the RPM package on Fedora 43:

```sh
sha256sum --check via-VERSION-linux-x86_64.rpm.sha256
sudo dnf install ./via-VERSION-linux-x86_64.rpm
```

On a Debian or Fedora system running systemd, the first installation enables
and starts `via.service`. Its default configuration listens on `:80` in debug
mode and serves a local welcome page. If the service cannot start, inspect it
with `systemctl status via`. Before using the service in production, edit
`/etc/via/example-config.yaml` and remove `debug: true`.

On Ubuntu 24.04, verify and install the binary archive:

```sh
sha256sum --check via-VERSION-linux-x86_64-bin.tar.xz.sha256
tar -xJf via-VERSION-linux-x86_64-bin.tar.xz
sudo install -m 0755 \
  via-VERSION-linux-x86_64-bin/via \
  /usr/local/bin/via
```

Replace `x86_64` with `aarch64` on an ARM64 system. Release binaries include
TLS support.

### Installer fallback

As a last resort when manual installation is not suitable, run:

```sh
curl -fsSL https://via.makridenko.com/install.sh | sh
```

The installer supports x86-64 and ARM64 versions of Debian 13, Fedora 43, and
Ubuntu 24.04. It detects the system, downloads the latest matching release,
verifies its SHA-256 checksum, and performs the same installation described
above.

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
