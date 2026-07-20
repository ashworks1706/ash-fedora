#!/usr/bin/env bash

set -euo pipefail

inhibitor_pid_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/remote-services-inhibit.pid"
refresh_interval="${REFRESH_INTERVAL:-3}"
remote_toggle_script="$HOME/.config/hypr/scripts/RemoteServices.sh"
wayvnc_log_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/wayvnc.log"

on_exit() {
  echo
  echo "Stopping remote mode and restoring normal sleep..."

  if [[ -x "$remote_toggle_script" ]]; then
    "$remote_toggle_script" --stop --no-dashboard
  else
    echo "Remote toggle script not found: $remote_toggle_script"
  fi

  exit 0
}

trap on_exit INT TERM

tailscaled_state() {
  local active enabled

  active="$(systemctl is-active tailscaled 2>/dev/null || true)"
  enabled="$(systemctl is-enabled tailscaled 2>/dev/null || true)"

  [[ -z "$active" ]] && active="unknown"
  [[ -z "$enabled" ]] && enabled="unknown"

  printf "%-12s active=%-10s enabled=%s\n" "tailscaled" "$active" "$enabled"
}

wayvnc_state() {
  local entries
  entries="$(pgrep -af '^wayvnc' || true)"

  if [[ -n "$entries" ]]; then
    echo "wayvnc      active=running"
    echo "$entries" | sed 's/^/  /'
  else
    echo "wayvnc      active=inactive"
    echo "  none"
  fi
}

wayvnc_clients() {
  local clients
  clients="$(wayvncctl client-list 2>/dev/null || true)"

  if [[ -n "$clients" ]]; then
    echo "$clients" | sed 's/^/  /'
  else
    echo "  none"
  fi
}

inhibitor_state() {
  if [[ -f "$inhibitor_pid_file" ]]; then
    local pid
    pid="$(cat "$inhibitor_pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "  active (pid $pid)"
      return
    fi
  fi

  echo "  inactive"
}

tailscale_info() {
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "  tailscale command not found"
    return
  fi

  local ipv4
  ipv4="$(tailscale ip -4 2>/dev/null || true)"
  if [[ -n "$ipv4" ]]; then
    echo "$ipv4" | sed 's/^/  /'
  else
    echo "  unavailable"
  fi
}

quick_tips() {
  local first_ip
  first_ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"

  echo "Quick commands"
  echo "  Start one-session mode:  ~/.config/hypr/scripts/RemoteServices.sh --start"
  echo "  Stop one-session mode:   ~/.config/hypr/scripts/RemoteServices.sh --stop"
  echo "  Check services:          systemctl status tailscaled --no-pager"
  echo "  Check listener:          ss -tln | rg 5900"
  echo "  WayVNC log (last 80):    tail -n 80 $wayvnc_log_file"
  echo "  WayVNC clients:          wayvncctl client-list"
  echo "  Disconnect one client:   wayvncctl client-disconnect <id>"
  echo "  Outputs:                 wayvncctl output-list"
  echo "  Switch output:           wayvncctl output-set DP-2"
  echo "  Kill WayVNC:             pkill wayvnc"
  if [[ -n "$first_ip" ]]; then
    echo "  VNC target:              ${first_ip}:5900"
  fi
}

while true; do
  printf '\033[H'
  echo "Remote Services Dashboard"
  echo "$(date '+%Y-%m-%d %H:%M:%S')"
  echo

  echo "Services"
  tailscaled_state
  wayvnc_state
  echo

  echo "Tailscale IP"
  tailscale_info
  echo

  echo "WayVNC clients"
  wayvnc_clients
  echo

  echo "Sleep inhibitor"
  inhibitor_state
  echo

  quick_tips
  echo
  echo "Tip: Ctrl+C = stop remote mode + close dashboard"
  printf '\033[J'
  sleep "$refresh_interval"
done
