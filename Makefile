CRYSTAL ?= crystal
SHARDS ?= shards
MKDOCS ?= mkdocs
WRK ?= wrk

CONFIG ?= config.yaml
URL ?= http://127.0.0.1:8080/
VERSION ?= $(shell awk '$$1 == "version:" { print $$2; exit }' shard.yml)
ARCH ?= $(shell uname -m | sed -e 's/^amd64$$/x86_64/' -e 's/^arm64$$/aarch64/')
PACKAGE_ARCH ?= $(if $(filter aarch64,$(ARCH)),arm64,$(if $(filter x86_64,$(ARCH)),amd64,$(ARCH)))
DIST ?= dist
NFPM_VERSION ?= 2.47.0
NFPM_INSTALL_DIR ?= $(CURDIR)/.tools/nfpm/$(NFPM_VERSION)

ifeq ($(origin NFPM), undefined)
NFPM := $(NFPM_INSTALL_DIR)/nfpm
NFPM_PREREQUISITE := $(NFPM)

$(NFPM):
	NFPM_VERSION="$(NFPM_VERSION)" NFPM_INSTALL_DIR="$(NFPM_INSTALL_DIR)" \
		sh scripts/install-nfpm.sh
endif

.PHONY: all doctor check-openssl build build-http release release-http package-bin package-deb package-rpm run debug test test-http format format-check docs docs-serve pages-smoke check check-http benchmark clean

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

package-bin: release
	@mkdir -p "$(DIST)"
	@set -eu; \
	output='$(PACKAGE_OUTPUT)'; \
	if [ -z "$$output" ]; then output='$(DIST)/via-$(VERSION)-linux-$(ARCH)-bin.tar.xz'; fi; \
	directory=$$(dirname "$$output"); filename=$$(basename "$$output"); \
	case "$$filename" in \
		*.tar.xz) package=$${filename%.tar.xz} ;; \
		*) echo "Binary package output must end in .tar.xz: $$output" >&2; exit 1 ;; \
	esac; \
	mkdir -p "$$directory"; \
	staging=$$(mktemp -d "$$directory/.via-package.XXXXXX"); \
	trap 'rm -rf "$$staging"' EXIT; \
	mkdir "$$staging/$$package"; \
	install -m 0755 bin/via "$$staging/$$package/via"; \
	cp CHANGELOG.md LICENSE README.md "$$staging/$$package/"; \
	tar \
		--sort=name \
		--owner=0 \
		--group=0 \
		--numeric-owner \
		--mtime=@0 \
		-C "$$staging" \
		-cf - "$$package" | xz --threads=1 > "$$output"; \
	(cd "$$directory" && sha256sum "$$filename" > "$$filename.sha256")

package-deb: release $(NFPM_PREREQUISITE)
	@mkdir -p "$(DIST)"
	@set -eu; \
	output='$(PACKAGE_OUTPUT)'; \
	if [ -z "$$output" ]; then output='$(DIST)/via-$(VERSION)-linux-$(ARCH).deb'; fi; \
	VERSION='$(VERSION)' PACKAGE_ARCH='$(PACKAGE_ARCH)' \
		$(NFPM) package --config packaging/nfpm.yaml --packager deb --target "$$output"; \
	directory=$$(dirname "$$output"); filename=$$(basename "$$output"); \
	(cd "$$directory" && sha256sum "$$filename" > "$$filename.sha256")

package-rpm: release $(NFPM_PREREQUISITE)
	@mkdir -p "$(DIST)"
	@set -eu; \
	output='$(PACKAGE_OUTPUT)'; \
	if [ -z "$$output" ]; then output='$(DIST)/via-$(VERSION)-linux-$(ARCH).rpm'; fi; \
	VERSION='$(VERSION)' PACKAGE_ARCH='$(PACKAGE_ARCH)' \
		$(NFPM) package --config packaging/nfpm.yaml --packager rpm --target "$$output"; \
	directory=$$(dirname "$$output"); filename=$$(basename "$$output"); \
	(cd "$$directory" && sha256sum "$$filename" > "$$filename.sha256")

run: build
	./bin/via run -c $(CONFIG)

debug: build
	./bin/via run --debug -c $(CONFIG)

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
	$(MKDOCS) build --strict --config-file web/mkdocs.yml
	cp web/index.html site/index.html
	cp web/styles.css site/styles.css
	mkdir -p site/assets
	cp web/docs/assets/favicon.svg web/docs/assets/site.css web/docs/assets/via-logo.svg site/assets/
	cp web/CNAME web/.nojekyll site/

docs-serve: docs build-http
	./bin/via run -c web/via.yaml

pages-smoke: docs build-http
	sh ./web/pages-smoke.sh

check: format-check test docs

check-http: format-check test-http docs

benchmark:
	$(WRK) -t4 -c128 -d30s --latency $(URL)

clean:
	rm -rf bin dist site
