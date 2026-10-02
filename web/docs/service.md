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
ExecStart=/usr/local/bin/via -c /etc/via/config/
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

Use absolute paths for `static`, `log_file`, certificates, and keys, or set
`WorkingDirectory` explicitly in the unit. After installing the unit:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now via
sudo systemctl status via
```

Via writes operational records to the journal by default. See
[Logs and troubleshooting](logging.md) for useful `journalctl` commands.
