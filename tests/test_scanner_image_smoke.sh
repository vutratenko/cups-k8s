#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER_IMAGE="${SCANNER_IMAGE:-registry.sion2k.ru/home/scanservjs-hplip:ci}"

docker build -t "$SCANNER_IMAGE" "$ROOT/image-scanner"
docker run --rm --entrypoint /bin/bash "$SCANNER_IMAGE" -c '
  command -v scanimage
  grep -qxF hpaio /etc/sane.d/dll.conf
  dpkg -l libsane-hpaio | grep -q ^ii
  ! pgrep -x ipp-usb >/dev/null 2>&1 || { echo "ipp-usb must not be running"; exit 1; }
'

echo "OK: scanner image smoke test passed"
