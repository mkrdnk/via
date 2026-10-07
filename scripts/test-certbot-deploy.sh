#!/bin/sh

# Exercise packaging/certbot-deploy.sh with the real OpenSSL CLI, but without
# a real Certbot, system group, or writes outside a temporary workspace.

set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper=$repository/packaging/certbot-deploy.sh
workspace=$(mktemp -d "${TMPDIR:-/tmp}/via-certbot-deploy-test.XXXXXX")
system_path=$PATH
test_bin=$workspace/bin
unprivileged_bin=$workspace/unprivileged-bin
tls_root=$workspace/tls
chown_log=$workspace/chown.log
openssl_command=${OPENSSL:-openssl}

cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_mode() {
  path=$1
  expected_mode=$2
  actual_mode=$(stat -c '%a' "$path")
  [ "$actual_mode" = "$expected_mode" ] ||
    fail "expected mode $expected_mode for $path, got $actual_mode"
}

assert_unchanged() {
  expected=$1
  actual=$2
  cmp -s "$expected" "$actual" ||
    fail "live PEM changed after a rejected deployment"
}

mkdir -p "$test_bin" "$unprivileged_bin"
openssl_path=$(command -v "$openssl_command") ||
  fail "OpenSSL executable is not available: $openssl_command"

cat >"$test_bin/id" <<'SH'
#!/bin/sh
printf '0\n'
SH

cat >"$unprivileged_bin/id" <<'SH'
#!/bin/sh
printf '1000\n'
SH

cat >"$test_bin/chown" <<'SH'
#!/bin/sh
set -eu
[ "$#" -ge 2 ] || exit 1
[ "$1" = "root:via" ] || exit 1
printf '%s\n' "$*" >>"$VIA_CHOWN_LOG"
SH

cat >"$test_bin/openssl" <<SH
#!/bin/sh
exec "$openssl_path" "\$@"
SH

chmod 0755 "$test_bin/id" "$unprivileged_bin/id" "$test_bin/chown" "$test_bin/openssl"

make_pair() {
  pair_directory=$1
  pair_common_name=$2
  mkdir -p "$pair_directory"
  "$openssl_path" req \
    -x509 \
    -newkey rsa:2048 \
    -nodes \
    -subj "/CN=$pair_common_name" \
    -days 1 \
    -keyout "$pair_directory/privkey.pem" \
    -out "$pair_directory/fullchain.pem" \
    >/dev/null 2>&1
}

run_helper() {
  hook_lineage=$1
  hook_certificate_name=$2
  RENEWED_LINEAGE="$hook_lineage" \
    VIA_CERTBOT_TLS_DIR="$tls_root" \
    VIA_CHOWN_LOG="$chown_log" \
    PATH="$test_bin:$system_path" \
    sh "$helper" "$hook_certificate_name"
}

primary_lineage=$workspace/lineages/example.com
make_pair "$primary_lineage" example.com

# First installation creates a combined PEM and the intended modes.
run_helper "$primary_lineage" example.com
live_pem=$tls_root/example.com/tls.pem
[ -f "$live_pem" ] || fail "first install did not create the live PEM"
grep -F -- 'BEGIN CERTIFICATE' "$live_pem" >/dev/null ||
  fail "live PEM does not contain a certificate"
grep -E -- 'BEGIN (RSA )?PRIVATE KEY' "$live_pem" >/dev/null ||
  fail "live PEM does not contain a private key"
assert_mode "$tls_root" 750
assert_mode "$tls_root/example.com" 750
assert_mode "$live_pem" 640
grep -F -- 'root:via' "$chown_log" >/dev/null ||
  fail "helper did not request root:via ownership"

# A renewal atomically replaces the live PEM with the newly generated pair.
cp "$live_pem" "$workspace/first.pem"
make_pair "$primary_lineage" example.com
run_helper "$primary_lineage" example.com
if cmp -s "$workspace/first.pem" "$live_pem"; then
  fail "renewal did not replace the live PEM"
fi
cp "$live_pem" "$workspace/renewed.pem"

# Malformed certificate input leaves the previous live PEM untouched.
printf 'not a PEM certificate\n' >"$primary_lineage/fullchain.pem"
if run_helper "$primary_lineage" example.com; then
  fail "malformed certificate was accepted"
fi
assert_unchanged "$workspace/renewed.pem" "$live_pem"

# A valid certificate paired with another key is also rejected without a swap.
mismatched_lineage=$workspace/lineages/mismatch
make_pair "$mismatched_lineage" mismatch
cp "$mismatched_lineage/fullchain.pem" "$primary_lineage/fullchain.pem"
if run_helper "$primary_lineage" example.com; then
  fail "mismatched certificate and key were accepted"
fi
assert_unchanged "$workspace/renewed.pem" "$live_pem"

# A valid leaf must not hide a damaged intermediate certificate.
cp "$mismatched_lineage/privkey.pem" "$primary_lineage/privkey.pem"
printf '\n-----BEGIN CERTIFICATE-----\ninvalid\n-----END CERTIFICATE-----\n' \
  >>"$primary_lineage/fullchain.pem"
if run_helper "$primary_lineage" example.com; then
  fail "malformed certificate chain was accepted"
fi
assert_unchanged "$workspace/renewed.pem" "$live_pem"

cp "$mismatched_lineage/fullchain.pem" "$primary_lineage/fullchain.pem"
printf 'not a private key\n' >"$primary_lineage/privkey.pem"
if run_helper "$primary_lineage" example.com; then
  fail "malformed private key was accepted"
fi
assert_unchanged "$workspace/renewed.pem" "$live_pem"

# Certbot defaults to ECDSA for new lineages; matching must not assume RSA.
"$openssl_path" req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -nodes -subj /CN=example.com -days 1 \
  -keyout "$primary_lineage/privkey.pem" -out "$primary_lineage/fullchain.pem" \
  >/dev/null 2>&1
run_helper "$primary_lineage" example.com
cp "$live_pem" "$workspace/renewed.pem"

# Failed deployments must remove their staged copies of the private key.
for temporary in "$tls_root/example.com"/.*; do
  case "${temporary##*/}" in .|..) continue ;; esac
  [ ! -f "$temporary" ] || fail "staged file was not cleaned up: $temporary"
done

# Restore valid inputs for argument and environment validation checks.
make_pair "$primary_lineage" example.com
if run_helper "$primary_lineage" ../example.com; then
  fail "path-like CERT_NAME was accepted"
fi
if run_helper "$primary_lineage" .hidden; then
  fail "hidden CERT_NAME was accepted"
fi
if RENEWED_LINEAGE="$primary_lineage" VIA_CERTBOT_TLS_DIR="$tls_root" PATH="$test_bin:$system_path" sh "$helper"; then
  fail "missing CERT_NAME was accepted"
fi
if RENEWED_LINEAGE= VIA_CERTBOT_TLS_DIR="$tls_root" PATH="$test_bin:$system_path" sh "$helper" example.com; then
  fail "missing RENEWED_LINEAGE was accepted"
fi
if run_helper "$mismatched_lineage" example.com; then
  fail "mismatched RENEWED_LINEAGE was accepted"
fi
if PATH="$unprivileged_bin:$test_bin:$system_path" sh "$helper" example.com; then
  fail "non-root invocation was accepted"
fi
assert_unchanged "$workspace/renewed.pem" "$live_pem"

printf 'certbot deploy helper tests passed\n'
