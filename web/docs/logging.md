# Logs and troubleshooting

Via writes its startup summary to stdout and operational logs to stderr. Each
log record is one line of `key=value` fields:

```text
time=2026-10-01T13:26:16.666Z level=info event=request.completed config_file="via.yaml" request_id="fbd06c3469d1c645432441b7816b52ad" client="127.0.0.1" method="GET" host="example.com" path="/api/users" target="proxy" route_path="/api" upstream="http://127.0.0.1:8000" status=200 response_bytes=421 duration_ms=4.691 failure=null
```

Query strings are not written to normal request logs, which avoids recording
tokens and other sensitive query parameters.

## Configure logging

Keep logs on stderr for systemd or a container, or append them to a file:

```yaml
log_file: /var/log/via.log
log_level: INFO
```

Supported levels are `DEBUG`, `INFO`, `WARN`, and `ERROR`. Names are
case-insensitive, and `WARNING` is accepted as an alias for `WARN`. The default
is `INFO`.

Relative `log_file` paths use Via's working directory. The parent directory must
already exist and be writable. `log_file` and `log_level` changes are applied
during configuration reload.

The effective level is selected in this order:

1. `--log-level`;
2. `--debug`, which selects `DEBUG`;
3. `log_level` in YAML;
4. the default `INFO`.

## Trace a failed request

Via generates a new request ID for every request. The same ID is:

- returned in the `X-Request-ID` response header;
- sent upstream in the `X-Request-ID` request header;
- shown on built-in error pages;
- included in Via's logs.

Use the ID shown to a client to find the corresponding request:

```sh
journalctl -u via -o cat | grep 'request_id="fbd06c3469d1c645432441b7816b52ad"'
```

## Common responses

| Status | Meaning |
| --- | --- |
| `400 Bad Request` | The request has no valid HTTP/1.1 `Host` header. |
| `403 Forbidden` | A route is configured with `proxy_pass: 403`. |
| `404 Not Found` | No route matches, or a static file does not exist. |
| `405 Method Not Allowed` | A static route received a method other than `GET` or `HEAD`. |
| `416 Range Not Satisfiable` | A static byte range is invalid or unavailable. |
| `502 Bad Gateway` | The upstream connection or WebSocket handshake failed before a valid response. |
| `503 Service Unavailable` | Debug mode is waiting for a valid replacement configuration. |

If a connection fails after response bytes or a WebSocket upgrade have started,
Via terminates the stream because it can no longer replace the response with an
error page.

## Debug a route or upstream

Run with debug logging:

```sh
via run --debug -c via.yaml
```

Debug records show the incoming request, selected route, upstream, and upstream
status. Debug mode also shows configuration errors in the browser when Via can
keep the listener running.

Typical events are:

- `routing.miss` — no route matched;
- `upstream.failed` — the upstream could not return a valid response;
- `stream.failed` — a connection failed after response streaming began;
- `config.rejected` — a replacement configuration was invalid.

See [Reload configuration](hot-reload.md) for the difference between production
and debug behavior after an invalid edit.

## systemd logs

When Via runs as a service, inspect its logs with:

```sh
journalctl -u via -o cat
journalctl -u via -o cat | grep 'event=request.completed'
```
