# Logging

Via writes operational logs as structured `key=value` records, one event per
line:

```text
time=2026-10-01T13:26:16.666Z level=info event=request.completed request_id="fbd06c3469d1c645432441b7816b52ad" client="127.0.0.1" method="GET" host="example.com" path="/api/users" target="proxy" route_path="/api" upstream="http://127.0.0.1:8000" status=200 request_bytes=null response_bytes=421 duration_ms=4.691 failure=null
```

Strings are quoted and escaped. Numbers, booleans, and `null` remain directly
machine-readable. A mutex keeps records from concurrent fibers on separate
lines.

The startup banner is written to stdout. By default, operational records are
written to stderr, which keeps logs suitable for systemd, containers, and shell
redirection:

```sh
via -c config.yaml >startup.log 2>via.log
```

To append operational records directly to a file, configure:

```yaml
log_file: /var/log/via.log
log_level: INFO
```

`log_level` is the minimum recorded severity:

| Level | Records |
| --- | --- |
| `DEBUG` | Debug, informational, warning, and error records |
| `INFO` | Informational, warning, and error records |
| `WARN` | Warning and error records |
| `ERROR` | Error records only |

Level names are case-insensitive, and `WARNING` is an alias for `WARN`. The
default is `INFO`. Relative `log_file` paths use Via's working directory, and
the parent directory must already exist. Via opens files in append mode and
flushes every record.

Both settings can change during hot reload. Via opens a replacement destination
before switching to it; if opening fails, the replacement configuration is
rejected and the previous destination remains active.

The effective level uses the following precedence:

1. `--log-level`;
2. `--debug`, which selects `DEBUG`;
3. `log_level` from YAML;
4. the default `INFO`.

For example, this keeps browser diagnostics enabled while recording only
errors:

```sh
via --debug --log-level ERROR -c config.yaml
```

## Request completion

Every handled request produces `request.completed` at `info` level:

```text
request_id
client
method
host
path
target
route_path
upstream
status
request_bytes
response_bytes
duration_ms
failure
```

Query strings are intentionally not logged. This avoids putting tokens or
other sensitive query parameters into normal operational logs.

`request_bytes` is `null` when the incoming body length is not known.
`response_bytes` uses the response content length when available and otherwise
tracks bytes streamed from an upstream.

## Configuration events

Via emits:

- `config.applied` after initial validation;
- `config.reloaded` after an atomic hot reload;
- `config.rejected` when a replacement configuration is invalid.

Rejected configuration records include whether Via kept a previous generation
and whether debug diagnostic mode was activated.

## Failure events

Transport and routing failures have dedicated events:

- `request.rejected`;
- `routing.miss`;
- `upstream.failed`;
- `stream.failed`.

All request-related events carry the same request ID returned in
`X-Request-ID` and shown on Via error pages.

## Debug mode

Unless `--log-level` is present, `--debug` sets the effective level to `DEBUG`
and adds:

- `request.started`;
- `routing.selected`;
- `upstream.response`.

These records expose route selection and upstream timing context without
changing the normal completion record.

```sh
via --debug -c config.yaml
```

## systemd

The default one-line format is directly searchable with `journalctl`:

```sh
journalctl -u via -o cat
journalctl -u via -o cat | grep 'event=request.completed'
journalctl -u via -o cat | grep 'request_id="fbd06c3469d1c645432441b7816b52ad"'
```
