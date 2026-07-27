#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP:$PATH"
export PRINTER_NAME=HP_DeskJet_3050_J610
export PRINTER_USB_VIDPID=03f0:9311
QUEUE_FLAG="$TMP/queue_exists"

cat >"$TMP/lpinfo" <<'EOF'
#!/usr/bin/env bash
echo "direct hp:/usb/Deskjet_3050_J610_series?serial=TEST"
EOF
chmod +x "$TMP/lpinfo"

cat >"$TMP/lpstat" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-p" && "\${2:-}" == "HP_DeskJet_3050_J610" ]]; then
  if [[ -f "$QUEUE_FLAG" ]]; then
    exit 0
  fi
  exit 1
fi
if [[ "\${1:-}" == "-r" ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$TMP/lpstat"

cat >"$TMP/lpadmin" <<EOF
#!/usr/bin/env bash
echo "lpadmin \$*" >> "$TMP/lpadmin_calls.log"
touch "$QUEUE_FLAG"
exit 0
EOF
chmod +x "$TMP/lpadmin"

for cmd in cupsaccept cupsenable lpoptions; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/$cmd"
  chmod +x "$TMP/$cmd"
done

# shellcheck disable=SC1091
source "$ROOT/image/entrypoint.sh"

rm -f "$TMP/lpadmin_calls.log" "$QUEUE_FLAG"

ensure_printer_queue
if ! grep -q 'HP_DeskJet_3050_J610' "$TMP/lpadmin_calls.log"; then
  echo "FAIL: lpadmin was not called for queue creation"
  exit 1
fi

ensure_printer_queue
count="$(grep -c 'lpadmin' "$TMP/lpadmin_calls.log" || true)"
if [[ "$count" -ne 1 ]]; then
  echo "FAIL: expected single lpadmin call on repeated bootstrap, got $count"
  exit 1
fi

echo "OK: ensure_printer_queue is idempotent"
