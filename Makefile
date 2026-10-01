CRYSTAL ?= crystal
SHARDS ?= shards
MKDOCS ?= mkdocs
WRK ?= wrk

CONFIG ?= config.yaml
URL ?= http://127.0.0.1:8080/

.PHONY: all build build-http release release-http run debug test test-http format format-check docs docs-serve check check-http benchmark clean

all: build

build:
	$(SHARDS) build

build-http:
	$(SHARDS) build -Dwithout_openssl

release:
	$(SHARDS) build --release --production --no-debug

release-http:
	$(SHARDS) build --release --production --no-debug -Dwithout_openssl

run: build
	./bin/via -c $(CONFIG)

debug: build
	./bin/via --debug -c $(CONFIG)

test:
	$(CRYSTAL) spec

test-http:
	$(CRYSTAL) spec -D without_openssl

format:
	$(CRYSTAL) tool format

format-check:
	$(CRYSTAL) tool format --check

docs:
	$(MKDOCS) build --strict

docs-serve:
	$(MKDOCS) serve

check: format-check test docs

check-http: format-check test-http docs

benchmark:
	$(WRK) -t4 -c128 -d30s --latency $(URL)

clean:
	rm -rf bin site
