#!/bin/sh
#
# Install a Certbot lineage as the single PEM file read by Via. Certbot calls
# deploy hooks as root and provides the renewed lineage in RENEWED_LINEAGE.

set -eu
umask 027

program=${0##*/}

die() {
  printf '%s: %s\n' "$program" "$*" >&2
  exit 1
}

[ "$#" -eq 1 ] || die "usage: $program CERT_NAME"
certificate_name=$1

# Certbot lineage names are directory basenames. Restrict the name further so
# it cannot select another destination directory.
case "$certificate_name" in
  [A-Za-z0-9]*)
    ;;
  *)
    die "CERT_NAME must begin with an ASCII letter or digit"
    ;;
esac
case "$certificate_name" in
  *[!A-Za-z0-9._-]*)
    die "CERT_NAME may contain only ASCII letters, digits, dots, underscores, and hyphens"
    ;;
esac

[ "$(id -u)" = "0" ] || die "must be run by Certbot as root"
command -v openssl >/dev/null 2>&1 || die "openssl command is required"

renewed_lineage=${RENEWED_LINEAGE:-}
[ -n "$renewed_lineage" ] || die "RENEWED_LINEAGE is required"
case "$renewed_lineage" in
  /*/)
    die "RENEWED_LINEAGE must not end with a slash"
    ;;
  /*)
    ;;
  *)
    die "RENEWED_LINEAGE must be an absolute Certbot lineage path"
    ;;
esac

lineage_name=${renewed_lineage##*/}
[ "$lineage_name" = "$certificate_name" ] ||
  die "RENEWED_LINEAGE does not match CERT_NAME"

certificate_file=$renewed_lineage/fullchain.pem
private_key_file=$renewed_lineage/privkey.pem
[ -f "$certificate_file" ] && [ -r "$certificate_file" ] ||
  die "certificate file is not readable: $certificate_file"
[ -f "$private_key_file" ] && [ -r "$private_key_file" ] ||
  die "private key file is not readable: $private_key_file"

# This override is intended for isolated integration tests. Production uses
# /etc/via/tls, so Via can read only the root:via-owned copy rather than the
# Certbot lineage itself.
tls_root=${VIA_CERTBOT_TLS_DIR:-/etc/via/tls}
case "$tls_root" in
  /*)
    ;;
  *)
    die "VIA_CERTBOT_TLS_DIR must be an absolute path"
    ;;
esac

destination_directory=$tls_root/$certificate_name
destination_file=$destination_directory/tls.pem

mkdir -p "$destination_directory"
chown root:via "$tls_root" "$destination_directory"
chmod 0750 "$tls_root" "$destination_directory"

staged_file=
certificate_public_key=
private_key_public_key=
cleanup() {
  rm -f "$staged_file" "$certificate_public_key" "$private_key_public_key"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

# All temporary files live beside the target, making the final rename atomic.
staged_file=$(mktemp "$destination_directory/.tls.pem.XXXXXX")
certificate_public_key=$(mktemp "$destination_directory/.certificate-public-key.XXXXXX")
private_key_public_key=$(mktemp "$destination_directory/.private-key-public-key.XXXXXX")

{
  cat "$certificate_file"
  printf '\n'
  cat "$private_key_file"
} >"$staged_file"

# Do not permit an encrypted key to make the non-interactive deploy hook wait
# for a passphrase. Validate the staged snapshot, not source files that Certbot
# might replace while this hook runs.
openssl x509 -in "$staged_file" -noout >/dev/null 2>&1 ||
  die "certificate is not valid PEM"
openssl crl2pkcs7 -nocrl -certfile "$staged_file" -out /dev/null >/dev/null 2>&1 ||
  die "certificate chain is not valid PEM"
openssl pkey -in "$staged_file" -passin pass: -check -noout >/dev/null 2>&1 ||
  die "private key is not valid unencrypted PEM"
openssl x509 -in "$staged_file" -pubkey -noout >"$certificate_public_key" 2>/dev/null ||
  die "could not read the certificate public key"
openssl pkey -in "$staged_file" -passin pass: -pubout >"$private_key_public_key" 2>/dev/null ||
  die "could not read the private key public key"
cmp -s "$certificate_public_key" "$private_key_public_key" ||
  die "certificate and private key do not match"

chown root:via "$staged_file"
chmod 0640 "$staged_file"
mv -fT -- "$staged_file" "$destination_file"
staged_file=

