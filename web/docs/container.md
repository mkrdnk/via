# Run in a container

The repository includes a multi-stage `Dockerfile` that builds Via from source
and copies only the executable and its runtime libraries into a small Alpine
image. The image runs as the unprivileged user `via` with UID and GID `10001`.

## Pull a release image

Release images are available from GitHub Container Registry for x86-64 and
ARM64. Replace `VERSION` with a published Via version:

```sh
docker pull ghcr.io/mkrdnk/via:VERSION
```

Stable releases are also tagged as `latest`.

## Build the image locally

Build for the host architecture:

```sh
docker build --tag via:local .
```

Docker can also build an image for a specific supported architecture:

```sh
docker buildx build --platform linux/amd64 --tag via:amd64 --load .
docker buildx build --platform linux/arm64 --tag via:arm64 --load .
```

## Configure and run Via

Create a configuration directory:

```sh
mkdir -p config
cat > config/via.yaml <<'YAML'
listen: ":8080"
proxy_pass: http://host.docker.internal:3000
YAML
```

Run the container and mount the directory at Via's default configuration path:

```sh
docker run --rm --name via \
  --publish 8080:8080 \
  --add-host host.docker.internal:host-gateway \
  --mount type=bind,source="$(pwd)/config",target=/etc/via,readonly \
  via:local
```

The `host.docker.internal` mapping lets Via reach a service listening on port
3000 of the Docker host. When the upstream runs in another container, attach
both containers to the same Docker network and use the upstream container or
Compose service name instead.

Mount the entire configuration directory rather than one file so atomic file
replacements remain visible to Via's configuration watcher. On an SELinux
system, give the bind mount an appropriate container file label.

## Check configuration and view logs

The image entrypoint is `via`, and its default command is `run`. Append another
Via command to override that default:

```sh
docker run --rm \
  --mount type=bind,source="$(pwd)/config",target=/etc/via,readonly \
  via:local check
```

Via writes operational logs to standard error by default, so they are available
through the container runtime:

```sh
docker logs via
```
