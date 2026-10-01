# Development and benchmarking

## Checks

The Makefile is the primary development entry point. Run the complete check:

```sh
make check
```

Useful targets:

```sh
make build          # development binary
make release        # optimized binary
make run            # run with CONFIG=config.yaml
make debug          # run --debug with CONFIG=config.yaml
make test
make format
make format-check
make docs
make docs-serve
```

Override `CONFIG` when running:

```sh
make debug CONFIG=/etc/via/config/
```

An HTTP-only build does not link OpenSSL:

```sh
make release-http
make test-http
make check-http
```

## Baseline benchmark

Start an upstream on port 3000, run Via with the minimal configuration, and use
a fixed payload and concurrency:

```sh
make benchmark URL=http://127.0.0.1:8080/
```

Record at least:

- requests per second;
- transfer rate;
- p50, p95, and p99 latency;
- CPU usage;
- maximum RSS;
- concurrent connection count.

Run each benchmark at least three times in release mode and compare medians.
Keep the host, upstream, payload, connection count, and benchmark duration
unchanged between revisions.

Performance work should follow profiling. The baseline exists to reveal
regressions and bottlenecks, not to support claims that Via is faster than
another proxy.
