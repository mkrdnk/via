#!/bin/sh
set -eu

case "${1:-}" in
  0|remove|purge)
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      systemctl daemon-reload >/dev/null 2>&1 || :
      systemctl reset-failed via.service >/dev/null 2>&1 || :
    fi
    ;;
esac
