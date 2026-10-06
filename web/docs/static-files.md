# Static files

Static routes serve files directly from a configured root:

```yaml
routes:
  - path: /
    static: ./dist
```

They support:

- `GET` and `HEAD`;
- MIME types based on filename;
- `index.html`;
- `ETag` and `Last-Modified`;
- `If-None-Match` and `If-Modified-Since`;
- single byte range requests;
- SPA fallback;
- protection against path traversal and symlink escapes.

Other methods receive `405 Method Not Allowed` with `Allow: GET, HEAD`.

## Path mapping

Via removes the matched route prefix when resolving a static file:

```yaml
routes:
  - path: /assets
    static: ./public
```

The request:

```text
/assets/css/app.css
```

maps to:

```text
<public>/css/app.css
```

Unlike static routes, `proxy_pass` routes forward the original path by default.
They only remove it when configured with `strip_prefix: true`.

A request for a directory without a trailing slash receives a permanent
redirect to the slash form. Via then looks for `index.html` inside the
directory. Directory listings are not generated.

## SPA fallback

Use the object form to serve a fallback when the requested file does not
exist:

```yaml
routes:
  - path: /
    static:
      root: ./dist
      fallback: index.html
```

The fallback must be a readable file inside `root`. Via validates it when
loading the configuration.

## Caching

Static responses include:

```text
ETag
Last-Modified
```

Matching `If-None-Match` or `If-Modified-Since` requests receive
`304 Not Modified`.

## Range requests

Via supports one `bytes` range, including open-ended and suffix forms:

```text
Range: bytes=100-199
Range: bytes=100-
Range: bytes=-100
```

A successful range receives `206 Partial Content`, `Content-Range`, and the
range `Content-Length`. Invalid, unsatisfiable, and multi-range requests
receive `416 Range Not Satisfiable`.

## Filesystem safety

Via URL-decodes the request path before resolving it. It rejects:

- `..` path segments, including percent-encoded traversal;
- NUL bytes;
- backslash separators;
- resolved paths outside the configured root;
- symlinks whose target is outside the configured root.

Files are streamed from disk and are not loaded into memory in full.
