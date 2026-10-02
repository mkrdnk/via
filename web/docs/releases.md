# Releases

Via publishes platform-specific x86_64 binaries through GitHub Releases.

## Supported release artifacts

Every release build produces:

```text
via-VERSION-fedora43-x86_64.tar.gz
via-VERSION-debian13-x86_64.tar.gz
via-VERSION-ubuntu24.04-x86_64.tar.gz
```

Each archive has a neighboring `.sha256` file. Archives contain:

- the `via` binary;
- `README.md`;
- `CHANGELOG.md`;
- `LICENSE`.

These builds include TLS support and are linked against the target
distribution's system libraries.

## Publishing a release

The version has one source of truth in `shard.yml`. Before tagging:

1. update `version` in `shard.yml`;
2. finalize the matching `CHANGELOG.md` section;
3. commit those changes;
4. create and push `vVERSION`.

Example:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow rejects a tag that does not equal `v` plus the shard
version.

## Workflow behavior

`.github/workflows/release.yml` calls the reusable build workflow for Fedora
43, Debian 13, and Ubuntu 24.04. It downloads all artifacts, verifies their
checksums, and then:

- creates a draft GitHub Release when none exists;
- replaces assets on an existing draft;
- uploads only missing assets to an already published release;
- validates an existing/new archive-checksum pair before completing a partial
  upload.

The draft must be reviewed and published in GitHub. Publishing the release
triggers the documentation deployment for the same tag.

## Verifying a download

```sh
sha256sum --check via-0.1.0-fedora43-x86_64.tar.gz.sha256
tar -xzf via-0.1.0-fedora43-x86_64.tar.gz
./via-0.1.0-fedora43-x86_64/via --version
```
