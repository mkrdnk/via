#!/bin/sh
set -eu

version="${CRYSTAL_VERSION:-1.21.1}"
install_dir="${CRYSTAL_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/crystal}"
machine="$(uname -m)"

case "$machine" in
  x86_64 | amd64)
    architecture="x86_64"
    ;;
  aarch64 | arm64)
    architecture="aarch64"
    ;;
  *)
    echo "Unsupported Crystal architecture: $machine" >&2
    exit 1
    ;;
esac

archive="crystal-${version}-1-linux-${architecture}-bundled.tar.gz"
url="https://github.com/crystal-lang/crystal/releases/download/${version}/${archive}"

rm -rf "$install_dir"
mkdir -p "$install_dir"
curl --fail --location --retry 3 --output "/tmp/$archive" "$url"
tar -xzf "/tmp/$archive" --strip-components=2 -C "$install_dir"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$install_dir/bin" >> "$GITHUB_PATH"
fi

"$install_dir/bin/crystal" --version
"$install_dir/bin/shards" --version
