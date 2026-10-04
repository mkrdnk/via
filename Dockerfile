ARG CRYSTAL_VERSION=1.21.1
ARG ALPINE_VERSION=3.22

FROM crystallang/crystal:${CRYSTAL_VERSION}-alpine AS builder

RUN apk add --no-cache \
      build-base \
      gc-dev \
      libevent-dev \
      openssl-dev \
      pcre2-dev \
      yaml-dev \
      zlib-dev

WORKDIR /src

COPY shard.yml ./
COPY src/ src/
COPY web/docs/assets/favicon.svg web/docs/assets/favicon.svg

RUN shards build --release --production --no-debug

FROM alpine:${ALPINE_VERSION} AS runtime

RUN apk add --no-cache \
      ca-certificates \
      gc \
      libgcc \
      libssl3 \
      pcre2 \
      yaml \
      zlib \
    && printf 'via:x:10001:10001:Via:/nonexistent:/usr/sbin/nologin\n' >> /etc/passwd \
    && printf 'via:x:10001:\n' >> /etc/group

COPY --from=builder /src/bin/via /usr/local/bin/via
COPY LICENSE /usr/share/doc/via/LICENSE

USER 10001:10001

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/via"]
CMD ["run"]
