#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?container image is required}"
CTR="${CTR:-/usr/local/bin/ctr}"

if "$CTR" -n k8s.io images list -q | grep -Fqx "$IMAGE"; then
  exit 0
fi

pull_args=()
if [[ -n "${REGISTRY_AUTH:-}" ]]; then
  pull_args+=(--user "$REGISTRY_AUTH")
fi

"$CTR" -n k8s.io images pull "${pull_args[@]}" "$IMAGE"
