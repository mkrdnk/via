# TLS

Via supports manual TLS termination for HTTP/1.1:

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
reload. Via creates a complete replacement OpenSSL server context before
publishing the configuration.

Each newly accepted connection snapshots the current context:

- existing TLS connections continue with their established session;
- new connections use the replacement certificate;
- a certificate or key loading error keeps the previous context in production;
- debug mode enters diagnostic state after a reload error.

Enabling or disabling TLS changes the listener transport and therefore
requires restarting Via. Changing `listen` also requires a restart.

## Current scope

Via currently supports one certificate context for the listener. SNI-based
multiple certificates and ACME automation are intentionally outside this
milestone.

OpenSSL development libraries are required for a normal build. Use
`make release-http` only when TLS support and HTTPS upstreams are not needed.
