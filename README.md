# Via

**Via is a tiny HTTP reverse proxy for when you only need `proxy_pass`.**

The current `v0.1` milestone provides a single-upstream HTTP reverse proxy with
streaming request and response bodies.

## Install

Via requires Crystal 1.21.1 or newer. A normal build also needs the OpenSSL
development libraries used by Crystal's HTTPS client.

```sh
shards build --release
```

The binary is written to `bin/via`.

For an HTTP-only binary on a machine without OpenSSL development libraries:

```sh
shards build --release -Dwithout_openssl
```

## Configure

Create `via.yaml`:

```yaml
listen: ":8080"
proxy_pass: http://localhost:3000
```

`listen` accepts `:PORT`, `HOST:PORT`, and `[IPv6]:PORT`. The `proxy_pass`
URL must use HTTP or HTTPS. This first milestone preserves the incoming path
and query unchanged and does not accept a path in `proxy_pass`.

## Run

```sh
bin/via -c via.yaml
```

Via forwards methods, paths, queries, end-to-end headers, status codes, and
bodies. It is a concurrent I/O proxy: each accepted client connection runs in
an independent Crystal fiber, socket waits yield to the runtime scheduler, and
there is no global request lock. Bodies are streamed with backpressure rather
than buffered in memory. Client and upstream HTTP/1.1 connections support
keep-alive; idle upstream connections are reused.

```sh
bin/via --help
bin/via --version
```

## Development

```sh
crystal spec
crystal tool format --check
```

## Baseline benchmark

Start an upstream on port 3000, run Via with the example above, and use a
fixed payload and concurrency so later changes remain comparable:

```sh
wrk -t4 -c128 -d30s --latency http://127.0.0.1:8080/
```

Record requests/sec, transfer/sec, latency percentiles, CPU, and maximum RSS.
Run the benchmark at least three times in release mode and compare medians.
