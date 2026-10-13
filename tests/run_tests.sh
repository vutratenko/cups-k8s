#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0

assert_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing file $path"
    failures=$((failures + 1))
  else
    echo "OK: $path"
  fi
}

assert_grep() {
  local pattern="$1"
  local path="$2"
  if ! grep -qE "$pattern" "$path"; then
    echo "FAIL: $path does not match /$pattern/"
    failures=$((failures + 1))
  else
    echo "OK: $path contains $pattern"
  fi
}

echo "== static file checks =="
assert_file image/Dockerfile
assert_file image/entrypoint.sh
assert_file image/cupsd.conf
assert_file image/avahi-daemon.conf
assert_file image/avahi-services/airprint.service
assert_file deploy/base/kustomization.yaml
assert_file deploy/base/deployment.yaml
assert_file deploy/argocd/application.yaml

echo "== entrypoint idempotency =="
assert_grep 'lpadmin -p "\$PRINTER_NAME"' image/entrypoint.sh
assert_grep '03f0:9311' image/entrypoint.sh
assert_grep 'lpstat -p "\$PRINTER_NAME"' image/entrypoint.sh

echo "== cups config =="
assert_grep 'Listen 0.0.0.0:631' image/cupsd.conf
assert_grep 'DefaultShared yes' image/cupsd.conf
assert_grep 'WebInterface Yes' image/cupsd.conf
assert_grep 'BrowseLocalProtocols dnssd' image/cupsd.conf
assert_file image/cups-browsed.conf

echo "== discovery daemons =="
assert_grep 'start_avahi' image/entrypoint.sh
assert_grep 'start_cups_browsed' image/entrypoint.sh
assert_grep 'start_wsdd' image/entrypoint.sh

echo "== k8s pinning =="
assert_grep 'hostNetwork: true' deploy/base/deployment.yaml
assert_grep 'containerPort: 631' deploy/base/deployment.yaml
assert_grep 'pve-worker-2' deploy/base/deployment.yaml
assert_grep '/dev/bus/usb' deploy/base/deployment.yaml

echo "== systemd image bootstrap =="
assert_file deploy/systemd/pull-image.sh
assert_grep 'ExecStartPre=/opt/cups-k8s/pull-image.sh' deploy/systemd/cups-k8s.service
assert_grep 'images pull' deploy/systemd/pull-image.sh
assert_grep 'ExecStart=/usr/local/bin/ctr.*run' deploy/systemd/cups-k8s.service

echo "== scanner image =="
assert_file image-scanner/Dockerfile
assert_grep 'sbs20/scanservjs:v3.3.0' image-scanner/Dockerfile
assert_grep 'docker.io/' image-scanner/Dockerfile
assert_grep 'libsane-hpaio' image-scanner/Dockerfile
assert_grep 'hpaio' image-scanner/Dockerfile
assert_file image-scanner/entrypoint.sh
assert_grep 'dbus-daemon --system' image-scanner/entrypoint.sh

echo "== scanner k8s =="
assert_file deploy/base/scanner-deployment.yaml
assert_file deploy/base/scanner-service.yaml
assert_grep 'pve-worker-2' deploy/base/scanner-deployment.yaml
assert_grep '/dev/bus/usb' deploy/base/scanner-deployment.yaml
assert_grep 'hostPort: 8080' deploy/base/scanner-deployment.yaml
assert_grep 'privileged: true' deploy/base/scanner-deployment.yaml
assert_grep '/var/lib/scanservjs/output' deploy/base/scanner-deployment.yaml
if grep -q 'hostNetwork: true' deploy/base/scanner-deployment.yaml; then
  echo "FAIL: scanner deployment must not use hostNetwork"
  failures=$((failures + 1))
else
  echo "OK: scanner deployment has no hostNetwork"
fi

echo "== kustomize render =="
kubectl kustomize deploy/base >/dev/null

if [[ "$failures" -gt 0 ]]; then
  echo "Tests failed: $failures"
  exit 1
fi

echo "All static tests passed."
