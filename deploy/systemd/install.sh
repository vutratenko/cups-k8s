#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${IMAGE:-registry.sion2k.ru/home/cups-hplip:0.1.13}"

install -D -m 0644 "$ROOT/deploy/systemd/cups-k8s.service" /etc/systemd/system/cups-k8s.service
mkdir -p /var/lib/cups-k8s
systemctl daemon-reload
systemctl enable --now cups-k8s.service
systemctl --no-pager --full status cups-k8s.service || true
echo "CUPS should be available at ipp://$(hostname -f):631/"
