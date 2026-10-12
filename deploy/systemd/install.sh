#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${IMAGE:-registry.sion2k.ru/home/cups-hplip:0.1.14}"

install -D -m 0644 "$ROOT/deploy/systemd/cups-k8s.service" /etc/systemd/system/cups-k8s.service
install -D -m 0755 "$ROOT/deploy/systemd/pull-image.sh" /opt/cups-k8s/pull-image.sh
if [[ -n "${DOCKER_LOGIN:-}" && -n "${DOCKER_PASSWORD:-}" ]]; then
  install -d -m 0700 /etc/cups-k8s
  printf 'REGISTRY_AUTH=%q\n' "$DOCKER_LOGIN:$DOCKER_PASSWORD" > /etc/cups-k8s/registry.env
  chmod 0600 /etc/cups-k8s/registry.env
fi
mkdir -p /var/lib/cups-k8s
systemctl daemon-reload
systemctl enable --now cups-k8s.service
systemctl --no-pager --full status cups-k8s.service || true
echo "CUPS should be available at ipp://$(hostname -f):631/"
