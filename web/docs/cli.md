# CLI

Via uses the `run` command to start the proxy. Without `-c`, it loads YAML
configuration from `/etc/via/`:

```sh
via run
```

Override that default with one YAML file:

```sh
via run -c config.yaml
```

Or with a directory of configuration fragments:

```sh
via run -c /etc/via/config/
```

Via prints one startup summary after all configured listeners are bound:

```text
→ config     /etc/via/config/
→ listening  :80
→ listening  :443 (TLS)
→ upstream   localhost:3000

ready
```

The summary includes one `listening` row per listener. Multiple-route
configurations show the route count and each unique proxy or static target.
TLS and debug mode are marked explicitly.

The banner is written to stdout. Operational records are written to stderr by
default or to the configured `log_file`; see
[Logs and troubleshooting](logging.md).

## Commands

```text
via run [options]    Start the proxy
via check [options]  Validate configuration without starting the proxy
```

Both commands accept:

```text
-c PATH, --config=PATH  Configuration file or directory (default: /etc/via/)
--version               Print the Via version
-h, --help              Print command help
```

`via run` additionally accepts:

```text
--debug            Show diagnostics and verbose proxy logs
--log-level=LEVEL  Override the configured log level
```

`--log-level` accepts `DEBUG`, `INFO`, `WARN`, or `ERROR` case-insensitively;
`WARNING` is an alias for `WARN`.

## Validate configuration

Check the default `/etc/via/` configuration:

```sh
via check
```

Or check a specific file or directory:

```sh
via check -c config.yaml
```

A valid configuration exits with status `0` and is not bound to any listening
address. Invalid YAML, routes, listeners, static targets, or TLS files produce a
configuration error and a non-zero exit status.

## Debug mode

```sh
via run --debug -c config.yaml
```

Debug mode shows configuration diagnostics in the browser and adds request,
routing, and upstream details to logs. It overrides the configured `log_level`
with `DEBUG` unless `--log-level` provides an explicit CLI override. See
[Reload configuration](hot-reload.md).

`--debug` applies to every listener. To debug only one listener, set
`debug: true` in that listener's YAML configuration instead.

## Exit behavior

Configuration and listener errors produce a non-zero exit status. `SIGINT` and
`SIGTERM` stop all listeners gracefully.
