#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-registry.sion2k.ru/home/cups-hplip:ci}"

docker build -t "$IMAGE" "$ROOT/image"
docker run --rm --entrypoint /bin/bash "$IMAGE" -c '
  command -v lpinfo
  command -v lpadmin
  test -x /opt/cups-k8s/entrypoint.sh
  grep -qi 'deskjet_3050_j610' /usr/share/hplip/data/models/models.dat
'

echo "OK: image smoke test passed"
