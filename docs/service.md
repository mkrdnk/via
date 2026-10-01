# Running as a service

Via is foreground-first and handles `SIGINT` and `SIGTERM`, so a service
manager can supervise it directly.

Example systemd unit:

```ini
[Unit]
Description=Via HTTP Reverse Proxy
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/via -c /etc/via/config/
Restart=on-failure
User=via
Group=via

[Install]
WantedBy=multi-user.target
```

The configuration directory can be split into lexically ordered YAML
fragments. Via watches those files and applies valid changes atomically, so
routine configuration edits do not require a service restart.

The repository does not yet ship an OS package or install this unit
automatically. Create the service user, directories, binary, and unit through
your own deployment tooling.
