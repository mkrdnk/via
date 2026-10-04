#!/bin/sh
set -eu

version="${NFPM_VERSION:-2.47.0}"
install_dir="${NFPM_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/nfpm}"
base_url="https://github.com/goreleaser/nfpm/releases/download/v${version}"
download_dir="${RUNNER_TEMP:-/tmp}/nfpm-download"
machine="$(uname -m)"

case "$machine" in
  x86_64 | amd64)
    architecture="x86_64"
    ;;
  aarch64 | arm64)
    architecture="arm64"
    ;;
  *)
    echo "Unsupported nFPM architecture: $machine" >&2
    exit 1
    ;;
esac

archive="nfpm_${version}_Linux_${architecture}.tar.gz"

rm -rf "$install_dir" "$download_dir"
mkdir -p "$install_dir" "$download_dir"
curl --fail --location --retry 3 --output "$download_dir/$archive" "$base_url/$archive"
curl --fail --location --retry 3 --output "$download_dir/checksums.txt" "$base_url/checksums.txt"
(
  cd "$download_dir"
  grep "  $archive\$" checksums.txt > "$archive.sha256"
  test -s "$archive.sha256"
  sha256sum --check "$archive.sha256"
)
tar -xzf "$download_dir/$archive" -C "$install_dir" nfpm

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$install_dir" >> "$GITHUB_PATH"
fi

"$install_dir/nfpm" --version
