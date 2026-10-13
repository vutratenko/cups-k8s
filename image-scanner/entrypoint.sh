#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[scanner-k8s] $*"
}

start_dbus() {
  mkdir -p /run/dbus
  if [[ ! -S /run/dbus/system_bus_socket ]]; then
    log "starting system dbus-daemon for HPLIP/hpaio"
    dbus-daemon --system --fork
  fi
}

start_dbus
exec /opt/scanner-k8s/scanservjs-entrypoint.sh
