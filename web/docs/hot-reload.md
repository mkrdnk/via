# Reload configuration

Via watches the file or directory passed to `-c`:

```sh
via -c via.yaml
via -c /etc/via/config/
```

Saving a valid configuration applies it without restarting the process.
Directory mode watches additions, removals, renames, and updates of `.yaml` and
`.yml` files.

## Changes applied automatically

Via can reload:

- routes and upstreams;
- static targets;
- certificate and key paths;
- `log_file` and `log_level`.

Requests and WebSocket connections that are already active continue normally.
New requests use the replacement configuration.

Via validates the complete replacement before applying it. In normal operation,
an invalid edit is logged and the last valid configuration remains active.

## Changes that require a restart

Restart Via after:

- adding or removing a listener;
- changing a `listen` address;
- enabling or disabling TLS on a listener.

Changing the certificate or key used by an existing TLS listener does not
require a restart. Existing TLS connections keep their established session, and
new connections use the replacement certificate.

## Debug mode

Start debug mode while developing a configuration:

```sh
via --debug -c via.yaml
```

After an invalid edit, Via shows a `503 Service Unavailable` diagnostic page
when it can keep the listener running. The page includes the configuration
source, validation error, and request ID. Saving a valid configuration clears
the diagnostic state.

An initial configuration still cannot start when Via cannot determine a valid
listener, parse the YAML, or load the configured certificate and key.
