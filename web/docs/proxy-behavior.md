# Proxy behavior

Via acts as an HTTP intermediary rather than forwarding every byte of the
original HTTP message unchanged.

## Request target

The request method, path, and query are forwarded unchanged. Route matching
does not strip or rewrite the matched path prefix.

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

End-to-end request and response headers are otherwise preserved.

## Body streaming

Request bodies are passed to the upstream client as an `IO`; Via does not read
the complete upload before forwarding it. Response bodies are copied through a
fixed-size buffer and begin flowing to the client before the upstream response
is complete.

`Content-Length` is preserved when it is known and validated by the Crystal
HTTP transport. Bodies without a known length use HTTP/1.1 chunked framing.

If the downstream client disconnects, Via stops the transfer and discards the
affected upstream connection. If an upstream disconnects before returning a
response, Via returns `502 Bad Gateway`. Once response bytes have started,
an upstream failure terminates the partial response because its status can no
longer be replaced.

## Redirects

Via forwards upstream redirect statuses and `Location` headers unchanged. It
does not rewrite absolute or relative redirect targets.
