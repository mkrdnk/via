# Proxying and WebSockets

Via acts as an HTTP intermediary rather than forwarding every byte of the
original HTTP message unchanged.

## Request target

The request method, path, and query are forwarded unchanged by default. A proxy
route can remove its matched path prefix before forwarding:

```yaml
routes:
  - path: /api
    proxy_pass: http://localhost:8000
    strip_prefix: true
```

With this route, `/api/users` is sent upstream as `/users`. The query string is
preserved, and an exact request for `/api` is sent as `/`. Prefix stripping
also applies to WebSocket handshakes.

## Host and forwarding headers

Via applies the following request header policy:

- `Host` is set to the selected upstream authority, including a non-default
  port;
- `X-Forwarded-Host` is set to the original `Host` header;
- `X-Forwarded-Proto` is set by Via to the downstream scheme (`http` or
  `https`);
- the direct client IP is appended to `X-Forwarded-For`.

Via overwrites incoming `X-Forwarded-Host` and `X-Forwarded-Proto` values.
An existing `X-Forwarded-For` chain is retained and the direct peer address is
appended to it.

## Route header rules

Proxy routes can set or remove end-to-end headers in either direction:

```yaml
routes:
  - path: /api
    proxy_pass: http://localhost:8000
    headers:
      request:
        set:
          X-Service: api
        remove:
          - X-Powered-By
      response:
        set:
          X-Frame-Options: DENY
```

Request rules run after Via constructs its forwarding headers. Response rules
run after hop-by-hop headers have been removed. `set` replaces all existing
values for that header; `remove` deletes it regardless of name casing. The same
rules apply to WebSocket handshakes.

Transport headers and Via-managed forwarding headers cannot be changed by route
rules. See [Header manipulation](configuration.md#header-manipulation) for the
complete list.

## Server identity

Via adds this header to every response:

```http
Server: Via
```

The header intentionally omits the version number. Via replaces an upstream
`Server` value and does not allow response header rules to change or remove its
server identity. This policy also applies to static files, redirects, built-in
error pages, and WebSocket handshakes.

## Hop-by-hop headers

Via removes standard hop-by-hop headers in both directions:

- `Connection`;
- `Keep-Alive`;
- `Proxy-Authenticate`;
- `Proxy-Authorization`;
- `TE`;
- `Trailer`;
- `Transfer-Encoding`;
- `Upgrade`.

Headers named by the incoming `Connection` header are removed as well.
Each HTTP transport then applies the correct framing for its own connection.
This allows Via to receive a chunked body and send it onward with new chunk
framing instead of forwarding the original chunks.

End-to-end request and response headers are otherwise preserved unless changed
by the selected route's header rules.

## WebSockets

WebSocket proxying is automatic for routes with an HTTP or HTTPS upstream. No
route-specific option is required:

```yaml
routes:
  - path: /socket
    proxy_pass: http://localhost:3000
```

Via recognizes an HTTP/1.1 `GET` request as a WebSocket handshake when it
contains both `Upgrade: websocket` and the `Upgrade` token in `Connection`. It
then:

1. forwards the handshake with the normal `Host`, `X-Forwarded-*`, and
   `X-Request-ID` policy;
2. preserves `Sec-WebSocket-*` headers, including extension and subprotocol
   negotiation;
3. returns the upstream `101 Switching Protocols` response;
4. relays traffic in both directions until either connection closes.

Because Via relays the upgraded stream without decoding WebSocket frames, text,
binary, continuation, ping, pong, and close frames pass through unchanged.
Negotiated extensions are transparent as well.

An upstream HTTP rejection such as `401 Unauthorized` is returned as a normal
HTTP response, including its body. A connection or handshake failure before a
response produces `502 Bad Gateway`. Downstream TLS termination and HTTPS
upstreams work with WebSockets in the same way as ordinary requests.

## Body streaming

Via does not read a complete upload or download into memory before forwarding
it. Request and response bodies begin flowing as soon as data is available.

`Content-Length` is preserved when it is known and valid. Bodies without a
known length use HTTP/1.1 chunked framing.

If the downstream client disconnects, Via stops the transfer and discards the
affected upstream connection. If an upstream disconnects before returning a
response, Via returns `502 Bad Gateway`. Once response bytes have started,
an upstream failure terminates the partial response because its status can no
longer be replaced.

## Redirects

Via forwards upstream redirect statuses and `Location` headers unchanged. It
does not rewrite absolute or relative redirect targets.

## Limitations

Via does not currently provide configurable request or response header rules,
upstream timeouts, retries, or load balancing.
