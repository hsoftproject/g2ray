#!/bin/bash
set -euo pipefail

workspace_config=".devcontainer/config.json"
runtime_config="/etc/xray/g2ray.json"
supervisor="/usr/local/bin/xray-supervisor"
supervisor_source=".devcontainer/xray-supervisor.sh"
pid_file="/run/xray.pid"
restart_file="/run/xray.restart"
workspace_tmp=""
runtime_tmp=""

cleanup() {
  [[ -z "$workspace_tmp" ]] || rm -f "$workspace_tmp"
  [[ -z "$runtime_tmp" ]] || sudo rm -f "$runtime_tmp"
}
trap cleanup EXIT

if [[ -z "${CODESPACE_NAME:-}" ]]; then
  echo "CODESPACE_NAME is not set; run this inside GitHub Codespaces." >&2
  exit 1
fi

if [[ ! -f "$workspace_config" ]] || [[ ! -f "$supervisor_source" ]]; then
  echo "The workspace Xray configuration or supervisor script is missing." >&2
  exit 1
fi
if ! command -v jq >/dev/null || ! command -v gh >/dev/null \
  || ! command -v curl >/dev/null || ! command -v pgrep >/dev/null; then
  echo "This command requires jq, gh, curl, and pgrep." >&2
  exit 1
fi

if ! jq -e 'any(.inbounds[]; .protocol == "vless" and ((.settings.clients // []) | length > 0))' \
  "$workspace_config" >/dev/null; then
  echo "No VLESS client was found in $workspace_config." >&2
  exit 1
fi

port="$(jq -er '[.inbounds[] | select(.protocol == "vless") | .port][0] // empty' "$workspace_config")"
host="${CODESPACE_NAME}-${port}.app.github.dev"

if ! sudo test -x /usr/local/bin/xray; then
  if [[ ! -f ".devcontainer/setup.sh" ]]; then
    echo "Xray is not installed and .devcontainer/setup.sh is missing." >&2
    exit 1
  fi
  sudo bash .devcontainer/setup.sh
fi

if ! sudo test -x "$supervisor"; then
  sudo install -m 755 "$supervisor_source" "$supervisor"
fi

start_supervisor() {
  local running_pid

  if running_pid="$(sudo pgrep -f '[/]usr/local/bin/xray-supervisor' 2>/dev/null)" \
    && [[ -n "$running_pid" ]]; then
    return
  fi

  # Older containers may still have the original, unsupervised Xray process.
  local standalone_pids
  standalone_pids="$(sudo pgrep -f '^/usr/local/bin/xray run -c /etc/xray/g2ray.json$' 2>/dev/null || true)"
  if [[ -n "$standalone_pids" ]]; then
    while IFS= read -r running_pid; do
      [[ "$running_pid" =~ ^[0-9]+$ ]] || continue
      sudo kill -TERM "$running_pid"
    done <<< "$standalone_pids"
    sleep 1
  fi

  sudo bash -c 'nohup /usr/local/bin/xray-supervisor >>/var/log/xray-supervisor.log 2>&1 </dev/null &'
}

read_running_pid() {
  local candidate
  candidate="$(sudo cat "$pid_file" 2>/dev/null || true)"
  if [[ "$candidate" =~ ^[0-9]+$ ]] && sudo kill -0 "$candidate" 2>/dev/null; then
    printf '%s' "$candidate"
  fi
}

wait_for_xray() {
  local candidate
  for _ in {1..30}; do
    candidate="$(read_running_pid)"
    if [[ -n "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
    start_supervisor
    sleep 1
  done
  return 1
}

if ! gh codespace ports visibility "$port:public" --codespace "$CODESPACE_NAME"; then
  echo "Could not make port $port public; check GitHub CLI authentication and Codespaces access." >&2
  exit 1
fi

echo "[g2ray] Starting recovery; a new UUID will be tried until the endpoint responds. Press Ctrl+C to stop."
attempt=0
while true; do
  attempt=$((attempt + 1))
  new_id="$(cat /proc/sys/kernel/random/uuid)"

  workspace_tmp="$(mktemp "${workspace_config}.XXXXXX.json")"
  jq --arg id "$new_id" \
    '(.inbounds[] | select(.protocol == "vless") | .settings.clients[0].id) = $id' \
    "$workspace_config" > "$workspace_tmp"
  chmod --reference="$workspace_config" "$workspace_tmp"
  if ! /usr/local/bin/xray run -test -c "$workspace_tmp"; then
    echo "Generated Xray configuration is invalid; refusing to install it." >&2
    exit 1
  fi

  runtime_tmp="$(sudo mktemp /etc/xray/g2ray.json.XXXXXX)"
  sudo install -m 644 "$workspace_tmp" "$runtime_tmp"
  sudo mv -f "$runtime_tmp" "$runtime_config"
  runtime_tmp=""
  mv -f "$workspace_tmp" "$workspace_config"
  workspace_tmp=""

  old_pid="$(read_running_pid)"
  if [[ -n "$old_pid" ]]; then
    sudo touch "$restart_file"
    if ! sudo kill -TERM "$old_pid" && sudo kill -0 "$old_pid" 2>/dev/null; then
      echo "Could not signal the Xray process to reload its configuration." >&2
      exit 1
    fi
  else
    start_supervisor
  fi

  if ! new_pid="$(wait_for_xray)"; then
    echo "[g2ray] Attempt $attempt: Xray did not start; retrying with a new UUID in 5 seconds." >&2
    sleep 5
    continue
  fi

  for _ in {1..6}; do
    if response_code="$(curl --silent --show-error --output /dev/null \
      --write-out '%{http_code}' --connect-timeout 5 --max-time 10 \
      --max-redirs 0 "https://${host}:${port}/" 2>/dev/null)" \
      && [[ "$response_code" =~ ^[24][0-9][0-9]$ ]]; then
      printf '\n[g2ray] Endpoint responded with HTTP %s. New VLESS connection:\n' "$response_code"
      printf 'vless://%s@%s:%s?encryption=none&security=tls&type=xhttp&mode=packet-up&sni=%s&path=%%2F#g2ray\n\n' \
        "$new_id" "$host" "$port" "$host"
      exit 0
    fi
    sleep 5
  done

  echo "[g2ray] Attempt $attempt: endpoint did not respond; retrying with a new UUID." >&2
done
