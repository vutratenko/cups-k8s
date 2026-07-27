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
assert_grep 'BrowseLocalProtocols' image/cupsd.conf
assert_grep 'DefaultShared yes' image/cupsd.conf
assert_grep 'Listen \*:631' image/cupsd.conf

echo "== k8s pinning =="
assert_grep 'hostNetwork: true' deploy/base/deployment.yaml
assert_grep 'pve-worker-2' deploy/base/deployment.yaml
assert_grep '/dev/bus/usb' deploy/base/deployment.yaml

echo "== kustomize render =="
kubectl kustomize deploy/base >/dev/null

if [[ "$failures" -gt 0 ]]; then
  echo "Tests failed: $failures"
  exit 1
fi

echo "All static tests passed."
