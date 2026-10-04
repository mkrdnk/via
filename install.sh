#!/bin/sh
set -eu

repository="mkrdnk/via"
github_url="https://github.com/$repository"
install_method=""
installed_binary=""
temporary_directory=""

info() {
  printf '%s\n' "$*"
}

fail() {
  printf 'via installer: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$temporary_directory" ]; then
    rm -rf "$temporary_directory"
  fi
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    fail "installation requires root privileges; install sudo or run this script as root"
  fi
}

download() {
  source_url=$1
  destination=$2
  curl --fail --location --retry 3 --show-error --silent \
    --output "$destination" "$source_url"
}

resolve_version() {
  latest_url=$(curl --fail --location --retry 3 --show-error --silent \
    --output /dev/null --write-out '%{url_effective}' \
    "$github_url/releases/latest")

  case "$latest_url" in
    "$github_url"/releases/tag/*)
      release_tag=${latest_url##*/}
      ;;
    *)
      fail "could not determine the latest release from $latest_url"
      ;;
  esac

  version=${release_tag#v}
  case "$version" in
    "" | *[!0-9A-Za-z._-]*)
      fail "GitHub returned an invalid release version: $version"
      ;;
  esac
}

detect_platform() {
  system=$(uname -s)
  if [ "$system" != "Linux" ]; then
    fail "unsupported operating system: $system (only Linux is supported)"
  fi

  machine=$(uname -m)
  case "$machine" in
    x86_64 | amd64)
      architecture="x86_64"
      ;;
    aarch64 | arm64)
      architecture="aarch64"
      ;;
    *)
      fail "unsupported architecture: $machine (supported: x86_64, aarch64)"
      ;;
  esac

  os_release_file=${VIA_OS_RELEASE_FILE:-/etc/os-release}
  [ -r "$os_release_file" ] || fail "cannot identify this Linux distribution"

  ID=
  VERSION_ID=
  # The standard os-release file contains shell-compatible variable assignments.
  . "$os_release_file"

  case "${ID:-}:${VERSION_ID:-}" in
    debian:13)
      command -v apt-get >/dev/null 2>&1 ||
        fail "apt-get is required on Debian"
      command -v dpkg >/dev/null 2>&1 ||
        fail "dpkg is required on Debian"
      install_method="deb"
      ;;
    fedora:43)
      command -v dnf >/dev/null 2>&1 ||
        fail "dnf is required on Fedora"
      install_method="dnf"
      ;;
    ubuntu:24.04)
      install_method="archive"
      ;;
    *)
      fail "unsupported Linux distribution: ${ID:-unknown} ${VERSION_ID:-unknown} (supported: Debian 13, Fedora 43, Ubuntu 24.04)"
      ;;
  esac
}

select_artifact() {
  case "$install_method" in
    deb)
      artifact="via-${version}-linux-${architecture}.deb"
      ;;
    dnf)
      artifact="via-${version}-linux-${architecture}.rpm"
      ;;
    archive)
      artifact="via-${version}-linux-${architecture}-bin.tar.xz"
      ;;
  esac
}

verify_artifact() {
  if ! command -v sha256sum >/dev/null 2>&1; then
    fail "sha256sum is required to verify the downloaded release"
  fi
  if ! command -v awk >/dev/null 2>&1; then
    fail "awk is required to verify the downloaded release"
  fi

  checksum_file="$temporary_directory/$artifact.sha256"
  expected_checksum=$(
    awk -v expected="$artifact" '
      NF == 2 {
        name = $2
        sub(/^\*/, "", name)
        if (name == expected && length($1) == 64 && $1 !~ /[^0-9A-Fa-f]/) {
          checksum = tolower($1)
          matches++
        }
      }
      END {
        if (NR != 1 || matches != 1) {
          exit 1
        }
        print checksum
      }
    ' "$checksum_file"
  ) || fail "the checksum file does not describe $artifact"

  actual_checksum=$(sha256sum "$temporary_directory/$artifact")
  actual_checksum=${actual_checksum%% *}
  [ "$actual_checksum" = "$expected_checksum" ] ||
    fail "checksum verification failed for $artifact"

  info "$artifact: OK"
}

validate_binary() {
  binary_path=$1
  binary_version=$("$binary_path" --version 2>/dev/null) ||
    fail "the installed via binary could not be started"
  [ "$binary_version" = "via $version" ] ||
    fail "expected Via $version, but $binary_path reported: $binary_version"
}

install_artifact() {
  artifact_path="$temporary_directory/$artifact"

  case "$install_method" in
    deb)
      run_as_root env DEBIAN_FRONTEND=noninteractive \
        apt-get install --yes "$artifact_path"
      installed_binary="/usr/bin/via"
      ;;
    dnf)
      run_as_root dnf install --assumeyes "$artifact_path"
      installed_binary="/usr/bin/via"
      ;;
    archive)
      command -v tar >/dev/null 2>&1 ||
        fail "tar is required to unpack the release"
      command -v xz >/dev/null 2>&1 ||
        fail "xz is required to unpack the release"
      command -v install >/dev/null 2>&1 ||
        fail "install is required to copy the via binary"

      tar -xJf "$artifact_path" -C "$temporary_directory"
      binary="$temporary_directory/via-${version}-linux-${architecture}-bin/via"
      [ -f "$binary" ] || fail "the release archive does not contain the via binary"
      validate_binary "$binary"
      run_as_root install -m 0755 "$binary" /usr/local/bin/via
      installed_binary="/usr/local/bin/via"
      ;;
  esac

  validate_binary "$installed_binary"
}

main() {
  command -v curl >/dev/null 2>&1 || fail "curl is required"
  command -v mktemp >/dev/null 2>&1 || fail "mktemp is required"

  detect_platform
  resolve_version
  select_artifact

  temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/via-install.XXXXXX")
  trap cleanup 0
  trap 'exit 1' HUP INT TERM

  release_url="$github_url/releases/download/$release_tag"

  info "Installing Via $version for Linux $architecture ($install_method)..."
  download "$release_url/$artifact" "$temporary_directory/$artifact" ||
    fail "release $release_tag does not provide $artifact"
  download "$release_url/$artifact.sha256" "$temporary_directory/$artifact.sha256" ||
    fail "release $release_tag does not provide a checksum for $artifact"
  verify_artifact
  install_artifact

  info "Via $version was installed successfully."
  if [ "$install_method" = "archive" ]; then
    info "Run Via with: via run -c /path/to/via.yaml"
  elif command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    if systemctl is-active --quiet via.service; then
      info "The via service is running."
    else
      info "The via service is not running; inspect it with: systemctl status via"
    fi
  fi
}

main "$@"
