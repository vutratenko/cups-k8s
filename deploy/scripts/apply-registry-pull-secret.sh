#!/usr/bin/env bash
set -euo pipefail

NS="${1:-cups}"
SERVER="${DOCKER_SERVER:-registry.sion2k.ru}"
USER="${DOCKER_LOGIN:?set DOCKER_LOGIN}"
PASS="${DOCKER_PASSWORD:?set DOCKER_PASSWORD}"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NS" create secret docker-registry registry-sion2k-pull \
  --docker-server="$SERVER" \
  --docker-username="$USER" \
  --docker-password="$PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Applied registry-sion2k-pull in namespace $NS"
