CRYSTAL ?= crystal
SHARDS ?= shards
MKDOCS ?= mkdocs
WRK ?= wrk

CONFIG ?= config.yaml
URL ?= http://127.0.0.1:8080/

.PHONY: all doctor check-openssl build build-http release release-http run debug test test-http format format-check docs docs-serve pages-smoke check check-http benchmark clean

all: build

doctor:
	@printf 'Crystal: '; $(CRYSTAL) --version
	@printf 'OpenSSL development files: '; \
	if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libssl libcrypto; then \
		echo 'available'; \
	else \
		echo 'missing (TLS builds are unavailable; HTTP-only builds still work)'; \
	fi

check-openssl:
	@if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists libssl libcrypto; then \
		echo 'OpenSSL development files are required for TLS builds.' >&2; \
		echo 'Fedora:        sudo dnf install openssl-devel' >&2; \
		echo 'Debian/Ubuntu: sudo apt install libssl-dev pkg-config' >&2; \
		echo 'Or build without TLS: make build-http' >&2; \
		exit 1; \
	fi

build: check-openssl
	$(SHARDS) build

build-http:
	$(SHARDS) build -Dwithout_openssl

release: check-openssl
	$(SHARDS) build --release --production --no-debug

release-http:
	$(SHARDS) build --release --production --no-debug -Dwithout_openssl

run: build
	./bin/via -c $(CONFIG)

debug: build
	./bin/via --debug -c $(CONFIG)

test: check-openssl
	$(CRYSTAL) spec

test-http:
	$(CRYSTAL) spec -D without_openssl

format:
	$(CRYSTAL) tool format

format-check:
	$(CRYSTAL) tool format --check

docs:
	rm -rf site
	$(MKDOCS) build --strict
	cp web/index.html site/index.html
	cp web/styles.css site/styles.css
	mkdir -p site/assets
	cp docs/assets/favicon.svg docs/assets/site.css docs/assets/via-logo.svg site/assets/
	cp web/CNAME web/.nojekyll site/

docs-serve: docs build-http
	./bin/via -c .github/pages/via.yaml

pages-smoke: docs build-http
	sh ./scripts/pages-smoke.sh

check: format-check test docs

check-http: format-check test-http docs

benchmark:
	$(WRK) -t4 -c128 -d30s --latency $(URL)

clean:
	rm -rf bin site
