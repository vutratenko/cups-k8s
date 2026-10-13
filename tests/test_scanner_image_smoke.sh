#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER_IMAGE="${SCANNER_IMAGE:-registry.sion2k.ru/home/scanservjs-hplip:ci}"

docker build -t "$SCANNER_IMAGE" "$ROOT/image-scanner"
docker run --rm --entrypoint /bin/bash "$SCANNER_IMAGE" -c '
  command -v scanimage
  command -v dbus-daemon
  grep -qxF hpaio /etc/sane.d/dll.conf
  dpkg -l libsane-hpaio | grep -q ^ii
  test -x /opt/scanner-k8s/entrypoint.sh
  ! pgrep -x ipp-usb >/dev/null 2>&1 || { echo "ipp-usb must not be running"; exit 1; }
'
docker run --rm -d --name scanservjs-smoke "$SCANNER_IMAGE" >/dev/null
for i in $(seq 1 30); do
  if docker exec scanservjs-smoke test -S /run/dbus/system_bus_socket 2>/dev/null; then
    break
  fi
  sleep 1
done
docker exec scanservjs-smoke test -S /run/dbus/system_bus_socket
docker rm -f scanservjs-smoke >/dev/null

echo "OK: scanner image smoke test passed"
