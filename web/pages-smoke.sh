#!/bin/sh
set -eu

log_file="${TMPDIR:-/tmp}/via-pages-smoke.log"
docs_prefix="${DOCS_PREFIX:-/docs}"
via_bin="${VIA_BIN:-./bin/via}"
install_script="${INSTALL_SCRIPT:-install.sh}"

cmp "$install_script" site/install.sh
sh -n site/install.sh

"$via_bin" run -c web/via.yaml >"$log_file" 2>&1 &
via_pid=$!

cleanup() {
  kill -TERM "$via_pid" 2>/dev/null || true
  wait "$via_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

attempt=0
until curl --fail --silent --show-error --output /dev/null http://127.0.0.1:8080/; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    cat "$log_file"
    exit 1
  fi
  sleep 0.1
done

for path in \
  / \
  /install.sh \
  /styles.css \
  /assets/favicon.svg \
  /assets/site.css \
  "$docs_prefix/" \
  "$docs_prefix/configuration/" \
  "$docs_prefix/cli/" \
  "$docs_prefix/service/"
do
  curl --fail --silent --show-error --output /dev/null \
    "http://127.0.0.1:8080${path}"
done
