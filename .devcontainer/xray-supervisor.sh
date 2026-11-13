#!/bin/bash
set -euo pipefail

config="/etc/xray/g2ray.json"
pid_file="/run/xray.pid"
restart_file="/run/xray.restart"
child_pid=""

stop_xray() {
  if [[ -n "$child_pid" ]] && kill -0 "$child_pid" 2>/dev/null; then
    kill -TERM "$child_pid"
    wait "$child_pid" || true
  fi
  exit 0
}

trap stop_xray TERM INT

while true; do
  rm -f "$restart_file"
  /usr/local/bin/xray run -c "$config" &
  child_pid=$!
  printf '%s\n' "$child_pid" > "$pid_file"

  if wait "$child_pid"; then
    status=0
  else
    status=$?
  fi
  child_pid=""
  rm -f "$pid_file"

  if [[ -e "$restart_file" ]]; then
    continue
  fi
  exit "$status"
done
