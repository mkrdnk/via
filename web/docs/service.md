# Running as a service

Via is foreground-first and handles `SIGINT` and `SIGTERM`, so a service
manager can supervise it directly.

The DEB and RPM packages install this systemd unit:

```ini
[Unit]
Description=Via HTTP Reverse Proxy
Documentation=https://via.makridenko.com/docs/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/via run -c /etc/via
Restart=on-failure
RestartSec=2s
User=via
Group=via
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_DAC_READ_SEARCH
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_DAC_READ_SEARCH
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

This uses the `/etc/via/` configuration directory. The packages install
`example-config.yaml` and a welcome page, then enable and start the service when
systemd is running. A system user and group named `via` are created through
`systemd-sysusers`. Both configuration files are preserved during upgrades.

The directory can be split into lexically ordered YAML fragments. Via watches
those files and applies valid changes atomically, so routine configuration
edits do not require a service restart.

The packaged service keeps the process under the unprivileged `via` user.
`CAP_NET_BIND_SERVICE` permits listeners on ports such as 80 and 443, while
`CAP_DAC_READ_SEARCH` permits reading root-managed TLS files, including the
default Certbot paths under `/etc/letsencrypt/live/`. The latter bypasses normal
file and directory read checks but does not grant write access. Remove it from
a local unit override when every configured certificate, key, and static root
is already readable by `via`.

Use absolute paths for `static`, `log_file`, certificates, and keys, or set
`WorkingDirectory` explicitly in a unit override. The example configuration
enables `debug: true` so configuration errors are visible on the welcome page.
Before using Via in production, remove that setting from
`/etc/via/example-config.yaml`. Via applies the change automatically without a
service restart.

Inspect the running service with:

```sh
systemctl status via
```

Via writes operational records to the journal by default. See
[Logs and troubleshooting](logging.md) for useful `journalctl` commands.
