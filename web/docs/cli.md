# CLI

Run Via with one YAML file:

```sh
via -c config.yaml
```

Or with a directory of configuration fragments:

```sh
via -c /etc/via/config/
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

## Options

```text
-c PATH, --config=PATH  Path to a YAML file or configuration directory
--debug                 Show diagnostics and verbose proxy logs
--log-level=LEVEL       Override the configured log level
--version               Print the Via version
-h, --help              Print command help
```

`-c` is currently required. Via does not yet select `/etc/via/config/`
implicitly. `--log-level` accepts `DEBUG`, `INFO`, `WARN`, or `ERROR`
case-insensitively; `WARNING` is an alias for `WARN`.

## Debug mode

```sh
via --debug -c config.yaml
```

Debug mode shows configuration diagnostics in the browser and adds request,
routing, and upstream details to logs. It overrides the configured `log_level`
with `DEBUG` unless `--log-level` provides an explicit CLI override. See
[Reload configuration](hot-reload.md).

## Exit behavior

Configuration and listener errors produce a non-zero exit status. `SIGINT` and
`SIGTERM` stop all listeners gracefully.
