# GitHub Pages deployment

The project website is published at:

```text
https://via.makridenko.com/
```

GitHub Pages serves the production static artifact. Via is still part of every
deployment: the workflow builds the HTTP-only binary, starts Via with a static
route, and verifies the complete site through real HTTP requests before the
artifact can be uploaded.

The workflow runs when a GitHub Release is published and checks out that
release tag. Documentation therefore represents a published version rather
than an arbitrary commit from `master`. A manual dispatch remains available
for recovery.

The smoke-test configuration is
`.github/pages/via.yaml`:

```yaml
listen: "127.0.0.1:8080"

routes:
  - path: /
    static: ./site
```

Run the same workflow locally:

```sh
make pages-smoke
```

Or keep Via running as the preview server:

```sh
make docs-serve
```

## Repository settings

In GitHub, open **Settings → Pages** and configure:

1. Source: **GitHub Actions**.
2. Custom domain: `via.makridenko.com`.
3. Enable **Enforce HTTPS** after the certificate is issued.

## DNS

Create this DNS record for `makridenko.com`:

```text
Type:   CNAME
Name:   via
Target: mkrdnk.github.io
```

DNS and certificate provisioning happen outside the repository. The committed
`CNAME` file ensures the generated Pages artifact retains the custom domain.

## Workflow

`.github/workflows/pages.yml` performs:

1. checkout of the published release tag;
2. Crystal and MkDocs setup;
3. static site build;
4. HTTP-only Via build;
5. end-to-end requests through Via;
6. Pages artifact upload;
7. deployment to the `github-pages` environment.

GitHub Pages itself cannot execute the Via binary. Production bytes are served
by GitHub's Pages infrastructure; Via provides the canonical local server and
the deployment gate.
