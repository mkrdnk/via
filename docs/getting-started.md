# Getting started

## Requirements

Via requires Crystal 1.21.1 or newer. A normal build also needs the OpenSSL
development libraries used by Crystal's HTTPS client.

## Build

```sh
shards build --release
```

The binary is written to `bin/via`.

For an HTTP-only binary on a machine without OpenSSL development libraries:

```sh
shards build --release -Dwithout_openssl
```

## Create a configuration

Save the following as `via.yaml`:

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

## Run Via

```sh
bin/via -c via.yaml
```

Requests to `http://localhost:8080` are now proxied to
`http://localhost:3000`.

The CLI also exposes:

```sh
bin/via --help
bin/via --version
```

Continue with [Configuration and routing](configuration.md) to configure
multiple upstreams.
