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
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
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
`CAP_NET_BIND_SERVICE` permits listeners on ports such as 80 and 443. The
service deliberately does not bypass filesystem permissions: every static file,
TLS certificate, and private key must be accessible to `via`.

Use absolute paths for `static`, `log_file`, certificates, and keys, or set
`WorkingDirectory` explicitly in a unit override. The example configuration
enables `debug: true` so configuration errors are visible on the welcome page.
Before using Via in production, remove that setting from
`/etc/via/example-config.yaml`. Via applies the change automatically without a
service restart.

## Operate the service

Validate the complete configuration directory before or after an edit:

```sh
sudo via check -c /etc/via
```

Inspect service state and operational logs:

```sh
systemctl status via
journalctl -u via -o cat
```

Valid route and certificate changes reload automatically. Use
`sudo systemctl restart via` only for changes that alter listener topology, as
described in [Reload configuration](hot-reload.md).

## Certbot certificate permissions

Certbot normally protects `/etc/letsencrypt/live/` from service accounts.
The packaged `/usr/libexec/via/certbot-deploy` helper publishes a validated
certificate and key as one PEM bundle, readable only by `root` and the `via`
group. It does not relax permissions on Certbot's account or private keys.
Configure both TLS paths to use that bundle:

```yaml
tls:
  cert: /etc/via/tls/example.com/tls.pem
  key: /etc/via/tls/example.com/tls.pem
```

Follow [Let's Encrypt with Certbot](tls.md#lets-encrypt-with-certbot) for the
HTTP challenge route, first issuance, deploy-hook registration, and renewal
scheduler. Installing Via alone does not request certificates or enable
Certbot. Via automatically watches the deployed PEM; no restart hook is needed.

See [Logs and troubleshooting](logging.md) for request tracing and additional
`journalctl` commands.
