# TLS

Via supports TLS termination for HTTP/1.1 using certificate files. You can
manage them yourself or [automate issuance and renewal with Certbot](#lets-encrypt-with-certbot).

```yaml
listen: ":443"

tls:
  cert: /etc/via/cert.pem
  key: /etc/via/key.pem

proxy_pass: http://localhost:8000
```

The certificate file may contain a certificate chain. The private key must
match the leaf certificate. Via validates that both paths are readable and
asks OpenSSL to validate their contents before starting or reloading.

Requests accepted by a TLS listener are sent upstream with:

```text
X-Forwarded-Proto: https
```

The upstream itself may use either HTTP or HTTPS independently of downstream
TLS termination.

## Certificate reload

Changing `tls.cert` or `tls.key` triggers the normal debounced configuration
reload. Via loads and validates the replacement files before applying them:

- existing TLS connections continue with their established session;
- new connections use the replacement certificate;
- a certificate or key loading error keeps the previous certificate active;
- debug mode enters diagnostic state after a reload error.

Enabling or disabling TLS changes the listener transport and therefore
requires restarting Via. Changing `listen` also requires a restart.

## Let's Encrypt with Certbot

Certbot handles ACME account registration, issuance, and scheduled renewal.
Via serves HTTP-01 challenge files and reloads the deployed certificate without
a restart. No ACME credentials or Certbot process run inside Via.

This walkthrough targets the [packaged systemd service](service.md) on Linux.
It requires:

- a TLS-enabled Via build and the `via` service user/group;
- Certbot, the OpenSSL command-line tool, and GNU coreutils;
- DNS for every requested domain pointing to this server, including any AAAA
  records, and public access to TCP ports 80 and 443;
- root access for Certbot and its deploy hook.

HTTP-01 cannot issue wildcard certificates. One certificate can include
multiple names using repeated `-d` options. Via still uses one certificate per
listener, not separate certificates selected through SNI.

### 1. Serve the challenge over HTTP

Replace `example.com` and the email address below with your own values.
Create the webroot before validating the configuration:

```sh
sudo install -d -m 0755 /var/lib/via/acme/.well-known/acme-challenge
```

Create `/etc/via/10-http.yaml`:

```yaml
listen: ":80"
routes:
  - host: example.com
    path: /.well-known/acme-challenge
    static: /var/lib/via/acme/.well-known/acme-challenge
  - host: example.com
    path: /
    return: 301 https://example.com
```

Static routes remove their matched prefix, so the static root must point at
the **challenge directory**, while Certbot's `--webroot-path` below points at
`/var/lib/via/acme`. The longer challenge route takes precedence over the
redirect. This redirect goes to the HTTPS home page; it does not preserve the
request path. Repeat both routes for additional certificate domains.

Disable the packaged welcome configuration with `enable: false` in
`/etc/via/example-config.yaml`, and ensure every remaining enabled YAML file
declares its listener. Do not enable the HTTPS configuration yet: the
certificate does not exist.

```sh
sudo -u via via check -c /etc/via
sudo systemctl restart via
```

Adding the port 80 listener requires a restart. Check reachability from outside
the server before contacting Let's Encrypt:

```sh
printf 'acme-probe\n' | sudo tee /var/lib/via/acme/.well-known/acme-challenge/probe
curl --fail http://example.com/.well-known/acme-challenge/probe
sudo rm /var/lib/via/acme/.well-known/acme-challenge/probe
```

The response must be `acme-probe`, not a redirect or an application page.

### 2. Issue and deploy the certificate

DEB and RPM packages include `/usr/libexec/via/certbot-deploy`. For a
source installation, install the same helper from the repository:

```sh
sudo install -D -o root -g root -m 0755 \
  packaging/certbot-deploy.sh /usr/libexec/via/certbot-deploy
```

First test HTTP-01 against Let's Encrypt's staging environment. A dry run does
not save a certificate or run deploy hooks by default:

```sh
sudo certbot certonly --dry-run --webroot \
  --webroot-path /var/lib/via/acme \
  --cert-name example.com -d example.com \
  --email admin@example.com --agree-tos --non-interactive
```

Then issue the trusted certificate and register its deploy hook:

```sh
sudo certbot certonly --webroot \
  --webroot-path /var/lib/via/acme \
  --cert-name example.com -d example.com \
  --email admin@example.com --agree-tos --non-interactive \
  --deploy-hook '/usr/libexec/via/certbot-deploy example.com'
```

Use the same certificate name in `--cert-name` and the hook argument. Certbot
saves this hook with the renewal configuration. It is scoped to this lineage,
not installed globally for unrelated certificates.

The hook validates the certificate and private key, checks that they match,
and atomically replaces `/etc/via/tls/example.com/tls.pem`. This single PEM
contains **both the full chain and the private key**. It is owned by
`root:via`, mode `0640`, inside restricted directories. Do not expose it as
static content or make it world-readable. Via does not need access to
`/etc/letsencrypt`.

If the certificate already exists, Certbot may not issue it again and thus
may not invoke the hook. Deploy the existing lineage explicitly:

```sh
sudo env RENEWED_LINEAGE=/etc/letsencrypt/live/example.com \
  /usr/libexec/via/certbot-deploy example.com
```

For an existing lineage, explicitly save the hook and webroot settings.
Certbot 2.3.0 and newer provide `reconfigure`, which tests the settings against
staging before saving them:

```sh
sudo certbot reconfigure --cert-name example.com \
  --webroot --webroot-path /var/lib/via/acme \
  --deploy-hook '/usr/libexec/via/certbot-deploy example.com'
```

With older versions, test the new options first, then perform one live renewal
to persist them:

```sh
sudo certbot renew --cert-name example.com --dry-run \
  --webroot --webroot-path /var/lib/via/acme \
  --deploy-hook '/usr/libexec/via/certbot-deploy example.com'
sudo certbot renew --cert-name example.com --force-renewal \
  --webroot --webroot-path /var/lib/via/acme \
  --deploy-hook '/usr/libexec/via/certbot-deploy example.com'
```

Only force renewal once after a successful dry run; repeated live issuance can
hit CA rate limits. Verify that the renewal file contains the helper command
(Certbot may store it under the historical `renew_hook` name):

```sh
sudo grep -F '/usr/libexec/via/certbot-deploy example.com' \
  /etc/letsencrypt/renewal/example.com.conf
```

### 3. Enable HTTPS

Create `/etc/via/20-https.yaml`:

```yaml
listen: ":443"
tls:
  cert: /etc/via/tls/example.com/tls.pem
  key: /etc/via/tls/example.com/tls.pem
routes:
  - host: example.com
    path: /
    proxy_pass: http://127.0.0.1:3000
```

Both paths intentionally reference the same PEM bundle. Adjust the upstream
and add routes for any additional names on the certificate.

```sh
sudo -u via via check -c /etc/via
sudo systemctl restart via
curl --fail https://example.com/
```

This restart adds the HTTPS listener. Later certificate renewals do not need
a restart or reload signal.

### 4. Enable automatic renewal

Enable the renewal scheduler provided by your Certbot installation. For
example, Debian/Ubuntu packages commonly provide:

```sh
sudo systemctl enable --now certbot.timer
systemctl list-timers --all
sudo certbot renew --dry-run
```

Other distributions or Snap installations use different timer names or cron.
Verify the installed scheduler rather than creating a second one. Keep port
80 and the challenge route available for future renewals.

To exercise the saved deploy hook too, first check whether
`certbot renew --help all` lists `--run-deploy-hooks`. If supported:

```sh
sudo certbot renew --cert-name example.com --dry-run --run-deploy-hooks
```

With `--run-deploy-hooks`, Certbot passes the current live certificate to the
hook, not the untrusted staging certificate. Older versions without this flag
can test the two steps separately: run plain `certbot renew --dry-run`, then
run the explicit `RENEWED_LINEAGE` deployment command from step 2. Normal
successful renewals deploy automatically; Via detects the replacement PEM and
uses it for new connections.

Monitor the Certbot scheduler, `/var/log/letsencrypt/letsencrypt.log`, certificate
expiry, and `journalctl -u via -o cat`. A failed issuance leaves the existing
certificate in place. A hook failure also preserves the previously deployed
PEM, but Certbot may already have renewed its own copy: fix the error and rerun
the explicit deployment command rather than waiting for the next renewal.

## Limitations

Via supports one certificate and key pair per listener. SNI-based multiple
certificates and a built-in ACME client are not supported. Certificate
automation runs externally through Certbot.
