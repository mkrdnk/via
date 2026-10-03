#!/bin/sh
set -eu

if command -v systemd-sysusers >/dev/null 2>&1; then
  systemd-sysusers /usr/lib/sysusers.d/via.conf
fi

if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
  exit 0
fi

if ! (
  systemctl daemon-reload
  systemctl enable via.service
  if systemctl is-active --quiet via.service; then
    systemctl restart via.service
  else
    systemctl start via.service
  fi
); then
  echo "Via was installed, but via.service could not be started." >&2
  echo "Inspect the service with: systemctl status via.service" >&2
fi
