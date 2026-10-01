# Architecture

Via is a concurrent streaming I/O proxy.

Each accepted client connection runs in an independent Crystal fiber. Socket
waits yield to the Crystal runtime scheduler, and Via does not put requests
behind a global lock. Independent client connections can therefore make
progress concurrently.

## Request flow

```text
HTTP request
    ↓
Router
    ↓
Route
    ↓
Upstream connection pool
    ↓
HTTP upstream
```

The router is independent of the HTTP server and client transports. It only
selects a validated route from a hostname and path.

Each active upstream request owns its `HTTP::Client`; clients are never shared
concurrently between fibers. Successfully completed clients return to a
bounded idle pool and can reuse their keep-alive connections.

## Streaming and backpressure

Via passes the incoming request body directly to the upstream HTTP client. It
copies the upstream response through a fixed-size buffer instead of loading the
entire body into memory.

When either side becomes slower, socket writes suspend the current fiber and
backpressure propagates through the stream. Body size therefore does not
determine Via's buffering requirement.

Hop-by-hop headers are removed at each proxy boundary. End-to-end request and
response headers, methods, paths, queries, and response statuses are forwarded.
