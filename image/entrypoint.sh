#!/usr/bin/env bash
set -euo pipefail

export PRINTER_NAME="${PRINTER_NAME:-HP_DeskJet_3050_J610}"
export PRINTER_USB_VIDPID="${PRINTER_USB_VIDPID:-03f0:9311}"
export PRINTER_PPD="${PRINTER_PPD:-drv:///hpcups.drv/hp-deskjet_3050_j610_series.ppd}"
export WSDD_HOSTNAME="${WSDD_HOSTNAME:-pve-worker-2}"
export WSDD_WORKGROUP="${WSDD_WORKGROUP:-WORKGROUP}"

CUPS_STATE_DIR="${CUPS_STATE_DIR:-/var/lib/cups-k8s}"
CUPS_ETC="${CUPS_ETC:-/etc/cups}"

log() {
  echo "[cups-k8s] $*"
}

wait_for_file() {
  local path="$1"
  local timeout="${2:-60}"
  local i=0
  while [[ ! -e "$path" && $i -lt $timeout ]]; do
    sleep 1
    i=$((i + 1))
  done
  [[ -e "$path" ]]
}

init_state_dirs() {
  mkdir -p "$CUPS_STATE_DIR/etc-cups"
  mkdir -p /run/dbus /run/avahi-daemon /run/cups /var/spool/cups /var/cache/cups /var/log/cups

  if [[ ! -f "$CUPS_STATE_DIR/etc-cups/cups-files.conf" ]]; then
    cp -a /etc/cups/. "$CUPS_STATE_DIR/etc-cups/"
    cp /opt/cups-k8s/cupsd.conf "$CUPS_STATE_DIR/etc-cups/cupsd.conf"
    cp /opt/cups-k8s/cups-browsed.conf "$CUPS_STATE_DIR/etc-cups/cups-browsed.conf"
  fi

  cp -a "$CUPS_STATE_DIR/etc-cups/." /etc/cups/
  cp /opt/cups-k8s/cupsd.conf /etc/cups/cupsd.conf
  cp /opt/cups-k8s/cups-browsed.conf /etc/cups/cups-browsed.conf
}

sync_etc_state() {
  [[ -d /etc/cups && -w /etc/cups ]] || return 0
  mkdir -p "$CUPS_STATE_DIR/etc-cups"
  cp -a /etc/cups/. "$CUPS_STATE_DIR/etc-cups/"
  cp /opt/cups-k8s/cupsd.conf "$CUPS_STATE_DIR/etc-cups/cupsd.conf"
  cp /opt/cups-k8s/cups-browsed.conf "$CUPS_STATE_DIR/etc-cups/cups-browsed.conf"
}

start_dbus() {
  if [[ ! -S /run/dbus/system_bus_socket ]]; then
    dbus-daemon --system --fork
  fi
}

start_avahi() {
  if pgrep -x avahi-daemon >/dev/null; then
    log "avahi-daemon already running; skipping start"
    return 0
  fi
  cp /opt/cups-k8s/avahi-daemon.conf /etc/avahi/avahi-daemon.conf
  mkdir -p /etc/avahi/services
  cp /opt/cups-k8s/avahi-services/*.service /etc/avahi/services/ 2>/dev/null || true
  avahi-daemon --no-chroot --daemonize
  local i=0
  while ! pgrep -x avahi-daemon >/dev/null && [[ $i -lt 10 ]]; do
    sleep 1
    i=$((i + 1))
  done
  if ! pgrep -x avahi-daemon >/dev/null; then
    log "WARNING: avahi-daemon failed to start; LAN discovery may be unavailable"
  fi
}

start_cups_browsed() {
  if ! command -v cups-browsed >/dev/null 2>&1; then
    log "cups-browsed not installed; using cupsd DNS-SD only"
    return 0
  fi
  cups-browsed &
  local i=0
  while ! pgrep -x cups-browsed >/dev/null && [[ $i -lt 15 ]]; do
    sleep 1
    i=$((i + 1))
  done
  if pgrep -x cups-browsed >/dev/null; then
    log "cups-browsed running (DNS-SD / Bonjour publish)"
  else
    log "WARNING: cups-browsed failed to start"
  fi
}

default_route_iface() {
  ip route show default 2>/dev/null | awk 'NR==1 {print $5; exit}'
}

start_wsdd() {
  if ! command -v wsdd >/dev/null 2>&1; then
    log "wsdd not in container; use host cups-k8s-wsdd.service for Windows WSD"
    return 0
  fi
  if pgrep -x wsdd >/dev/null; then
    return 0
  fi
  local iface="${WSDD_INTERFACE:-$(default_route_iface)}"
  if [[ -z "$iface" ]]; then
    log "WARNING: no default route interface for wsdd; skipping WSD"
    return 0
  fi
  wsdd -d -i "$iface" -H "$WSDD_HOSTNAME" -w "$WSDD_WORKGROUP"
  sleep 1
  if pgrep -x wsdd >/dev/null; then
    log "wsdd running on $iface (Windows WSD discovery)"
  else
    log "WARNING: wsdd failed to start"
  fi
}

configure_cups_lan() {
  if ! lpstat -r >/dev/null 2>&1; then
    return 1
  fi
  cupsctl --remote-admin --remote-any --share-printers >/dev/null 2>&1 || true
  share_printers
  return 0
}

reload_cups_config() {
  if lpstat -r >/dev/null 2>&1; then
    cupsctl WebInterface=yes >/dev/null 2>&1 || true
    kill -HUP "$(cat /run/cups/cupsd.pid 2>/dev/null)" 2>/dev/null || true
  fi
}

start_cups() {
  if ! pgrep -x cupsd >/dev/null; then
    /usr/sbin/cupsd
  fi
  local i=0
  while ! lpstat -r >/dev/null 2>&1 && [[ $i -lt 30 ]]; do
    sleep 1
    i=$((i + 1))
  done
  lpstat -r
}

find_usb_uri() {
  lpinfo -v 2>/dev/null | awk '
    /^direct / {
      line = $0
      sub(/^direct /, "", line)
      if (index(line, "hp:/usb/") || index(line, "usb:/") || index(line, "Deskjet_3050") || index(line, "3050"))
        print line
    }
  ' | head -n1
}

ensure_printer_queue() {
  if lpstat -p "$PRINTER_NAME" >/dev/null 2>&1; then
    log "Queue $PRINTER_NAME already exists"
    return 0
  fi

  local uri=""
  local attempt=0
  while [[ -z "$uri" && $attempt -lt 120 ]]; do
    uri="$(find_usb_uri || true)"
    if [[ -z "$uri" ]]; then
      if wait_for_file /dev/usb/lp0 2; then
        uri="$(find_usb_uri || true)"
      fi
      sleep 2
      attempt=$((attempt + 1))
    fi
  done

  if [[ -z "$uri" ]]; then
    log "WARNING: USB printer not found (vid:pid $PRINTER_USB_VIDPID); will retry in background"
    return 1
  fi

  log "Adding queue $PRINTER_NAME with URI $uri"
  lpadmin -p "$PRINTER_NAME" -E -v "$uri" -m "$PRINTER_PPD" -L "Home LAN" -D "HP Deskjet 3050 J610 series"
  cupsaccept "$PRINTER_NAME"
  cupsenable "$PRINTER_NAME"
  lpoptions -d "$PRINTER_NAME" >/dev/null 2>&1 || true
  log "Queue $PRINTER_NAME ready"
  sync_etc_state
}

share_printers() {
  lpstat -p 2>/dev/null | awk '/printer/ {print $2}' | while read -r q; do
    lpadmin -p "$q" -o printer-is-shared=true || true
  done
}

discovery_ready=0

ensure_lan_discovery() {
  if [[ "$discovery_ready" -eq 1 ]]; then
    return 0
  fi
  if ! configure_cups_lan; then
    return 1
  fi
  start_cups_browsed
  start_wsdd
  reload_cups_config
  discovery_ready=1
  log "LAN web UI and discovery enabled"
}

bootstrap_loop() {
  while true; do
    if ensure_printer_queue; then
      ensure_lan_discovery || true
    fi
    sleep 30
  done
}

main() {
  init_state_dirs
  start_dbus
  start_avahi
  bootstrap_loop &
  exec /usr/sbin/cupsd -f
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
