# Development and benchmarking

## Checks

Run the test suite:

```sh
crystal spec
```

Check formatting:

```sh
crystal tool format --check
```

Build an optimized binary:

```sh
shards build --release
```

## Baseline benchmark

Start an upstream on port 3000, run Via with the minimal configuration, and use
a fixed payload and concurrency:

```sh
wrk -t4 -c128 -d30s --latency http://127.0.0.1:8080/
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
