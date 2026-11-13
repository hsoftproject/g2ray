#!/bin/bash
set -euo pipefail

config="/etc/xray/g2ray.json"
client_id="$(jq -er '[.inbounds[] | select(.protocol == "vless") | .settings.clients[]?.id][0] // empty' "$config")"
port="$(jq -er '[.inbounds[] | select(.protocol == "vless") | .port][0] // empty' "$config")"

if [[ -z "${CODESPACE_NAME:-}" ]]; then
  echo "CODESPACE_NAME is not set; start this script inside GitHub Codespaces." >&2
  exit 1
fi

gh codespace ports visibility "$port:public" --codespace "$CODESPACE_NAME"

host="${CODESPACE_NAME}-${port}.app.github.dev"

printf '\n\033[1;32m[g2ray]\033[0m Port %s is public. VLESS connection:\n' "$port"
printf 'vless://%s@%s:%s?encryption=none&security=tls&type=xhttp&mode=packet-up&sni=%s&path=%%2F#g2ray\n\n' \
  "$client_id" "$host" "$port" "$host"
