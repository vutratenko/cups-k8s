#!/usr/bin/env bash
set -euo pipefail

export PRINTER_NAME="${PRINTER_NAME:-HP_DeskJet_3050_J610}"
export PRINTER_USB_VIDPID="${PRINTER_USB_VIDPID:-03f0:9311}"
export PRINTER_PPD="${PRINTER_PPD:-drv:///sample.drv/hpcups.drv/HP-Deskjet-3050-J610-series.ppd}"

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
  mkdir -p "$CUPS_STATE_DIR"/{etc-cups,spool,run-cups,cache,logs}
  mkdir -p /run/dbus /run/avahi-daemon /var/run/cups /var/log/cups /var/cache/cups

  if [[ ! -f "$CUPS_STATE_DIR/etc-cups/cupsd.conf" ]]; then
    cp /opt/cups-k8s/cupsd.conf "$CUPS_STATE_DIR/etc-cups/cupsd.conf"
  fi

  rm -rf "$CUPS_ETC"
  ln -sfn "$CUPS_STATE_DIR/etc-cups" "$CUPS_ETC"
  ln -sfn "$CUPS_STATE_DIR/spool" /var/spool/cups
  ln -sfn "$CUPS_STATE_DIR/run-cups" /run/cups
  ln -sfn "$CUPS_STATE_DIR/cache" /var/cache/cups
  ln -sfn "$CUPS_STATE_DIR/logs" /var/log/cups
}

start_dbus() {
  if [[ ! -S /run/dbus/system_bus_socket ]]; then
    dbus-daemon --system --fork
  fi
}

start_avahi() {
  cp /opt/cups-k8s/avahi-daemon.conf /etc/avahi/avahi-daemon.conf
  mkdir -p /etc/avahi/services
  cp /opt/cups-k8s/avahi-services/*.service /etc/avahi/services/ 2>/dev/null || true
  avahi-daemon --no-chroot --daemonize
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
}

share_printers() {
  lpstat -p 2>/dev/null | awk '/printer/ {print $2}' | while read -r q; do
    lpadmin -p "$q" -o printer-is-shared=true || true
  done
}

bootstrap_loop() {
  while true; do
    if ensure_printer_queue; then
      share_printers
    fi
    sleep 30
  done
}

main() {
  init_state_dirs
  start_dbus
  start_avahi
  start_cups
  ensure_printer_queue || true
  share_printers
  bootstrap_loop &
  exec /usr/sbin/cupsd -f
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
