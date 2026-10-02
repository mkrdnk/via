# Debug mode and hot reload

Via watches its configuration automatically:

```sh
via -c via.yaml
via -c /etc/via/config/
```

File changes are debounced before Via reloads the complete configuration.
Directory mode watches additions, removals, renames, and updates of `.yaml`
and `.yml` files.

## Atomic reload

Via parses and validates a complete replacement configuration before changing
runtime state. A valid configuration is installed atomically: each new request
sees either the old generation or the new generation, never a partially
updated set of routes.

Requests already using the previous generation continue normally. Its idle
upstream connections are closed only after all active requests finish.

The listener cannot currently be rebound during hot reload. Changing `listen`
is treated as a configuration error and requires restarting Via.

TLS certificate and key paths may change during reload. Via loads the complete
replacement context before swapping runtime state, and new TLS connections use
the new certificate. TLS cannot be enabled or disabled without restarting the
listener.

`log_file` and `log_level` may also change during reload. Via opens a new log
file before switching destinations. If that fails, Via keeps both the previous
runtime generation and the previous logging destination. A `--log-level`
command-line override remains in effect across reloads.

## Production behavior

Without `--debug`, an invalid reload is written to the error log and Via keeps
serving with the last valid configuration:

```text
edit → invalid config → log error → keep previous config
```

An invalid initial configuration still prevents production startup.

## Debug behavior

Start development mode with:

```sh
via --debug -c via.yaml
```

If validation fails after Via can determine a valid `listen` address, Via
starts or enters a diagnostic state. Browser requests receive a detailed
`503 Service Unavailable` page containing:

- the configuration source;
- the validation error;
- a request ID;
- confirmation that Via is waiting for another edit.

Saving a valid configuration clears the diagnostic state and atomically
installs the new routes:

```text
edit → save → reload → works
```

Debug mode also logs request method, request target, selected upstream,
upstream status, and request ID.

An initial file that cannot be parsed as YAML, does not contain a valid
`listen`, or configures TLS without a usable certificate cannot start a
listener and therefore still exits with an error.
