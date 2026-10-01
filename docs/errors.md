# Error pages and request IDs

Via embeds its error pages in the executable. They do not depend on static
assets or files installed next to the binary.

The error page renderer supports:

- `400 Bad Request`;
- `404 Not Found`;
- `405 Method Not Allowed`;
- `416 Range Not Satisfiable`;
- `502 Bad Gateway`;
- `503 Service Unavailable`;
- `504 Gateway Timeout`.

`503` is reserved for temporarily unavailable runtime state, and `504` will be
used by configurable upstream timeouts. Those conditions are not emitted yet.

Error responses are self-contained HTML pages. The Via favicon is embedded in
the binary and referenced through a data URI, so it works even when no static
route or external asset directory is available.

The visible page remains intentionally minimal:

```text
via

502
Bad Gateway

The upstream server could not be reached.

Request ID: 8efb1e82e14bd13639d777ca8b17e843
```

Debug configuration diagnostics use the same layout and favicon.

## Request IDs

Via generates a cryptographically random 128-bit request ID for every request.
It does not trust a client-supplied ID.

The same lowercase hexadecimal ID is:

- returned in the `X-Request-ID` response header;
- sent to the upstream in the `X-Request-ID` request header;
- printed on built-in error pages;
- included in Via's error log entry.

This makes a browser-visible failure traceable to the corresponding proxy log
and upstream request.

## Failure behavior

Via currently emits:

- `400` when an HTTP/1.1 request has no valid `Host` header;
- `404` when no route matches;
- `405` for unsupported methods on static routes;
- `416` for invalid or unsatisfiable static byte ranges;
- `502` when the selected upstream cannot be reached or disconnects before
  returning a response.

If an upstream or downstream disconnect happens after response bytes have
started, Via cannot replace the response with an error page. It terminates the
partial stream and logs the failure with its request ID.
