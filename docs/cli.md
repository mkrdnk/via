# CLI

Run Via with one YAML file:

```sh
via -c config.yaml
```

Or with a directory of configuration fragments:

```sh
via -c /etc/via/config/
```

Via prints one startup summary after the listener is bound:

```text
██▄       ▄██    ▄██▄
 ▀██▄   ▄██▀    ██  ██
   ██▄ ▄██     ██    ██
    ▀███▀     ██      ██    via 0.1.0

→ config     /etc/via/config.yaml
→ listening  :8080
→ upstream   localhost:3000

ready
```

Multiple-route configurations show the route count and each unique proxy or
static target. TLS and debug mode are marked explicitly.

## Options

```text
-c PATH, --config=PATH  Path to a YAML file or configuration directory
--debug                 Show diagnostics and verbose proxy logs
--version               Print the Via version
-h, --help              Print command help
```

`-c` is currently required. Via does not yet select `/etc/via/config/`
implicitly.

## Debug mode

```sh
via --debug -c config.yaml
```

Debug mode shows configuration diagnostics in the browser and adds request,
routing, and upstream details to logs. See
[Debug mode and hot reload](hot-reload.md).

## Exit behavior

Configuration and listener errors produce a non-zero exit status. `SIGINT` and
`SIGTERM` stop the listener and retire the active runtime generation.
