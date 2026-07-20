#!/usr/bin/env bash

set -euo pipefail

system_services=(tailscaled)
inhibitor_pid_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/remote-services-inhibit.pid"
inhibitor_reason="Remote access active (tailscaled+wayvnc)"
dashboard_script="$HOME/.config/hypr/scripts/RemoteServicesDashboard.sh"
wayvnc_pid_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/wayvnc.pid"
wayvnc_log_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/wayvnc.log"
wayvnc_output="${WAYVNC_OUTPUT:-}"
wayvnc_port="${WAYVNC_PORT:-5900}"
wayvnc_use_gpu="${WAYVNC_USE_GPU:-1}"

mode="toggle"
open_dashboard=true

while (( $# > 0 )); do
  case "$1" in
    --toggle)
      mode="toggle"
      ;;
    --start)
      mode="start"
      ;;
    --stop)
      mode="stop"
      ;;
    --no-dashboard)
      open_dashboard=false
      ;;
    *)
      ;;
  esac
  shift
done

notify() {
  local title="$1"
  local body="$2"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Hyprland" -u low "$title" "$body"
  else
    printf "%s: %s\n" "$title" "$body"
  fi
}

notify "Remote services" "Request received (${mode})..."

get_tailscale_ip() {
  tailscale ip -4 2>/dev/null | head -n1
}

detect_focused_output() {
  if [[ -n "$wayvnc_output" ]]; then
    printf "%s\n" "$wayvnc_output"
    return 0
  fi

  if command -v hyprctl >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
      local focused
      focused="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' | head -n1)"
      if [[ -n "$focused" && "$focused" != "null" ]]; then
        printf "%s\n" "$focused"
        return 0
      fi
    fi

    local focused_text
    focused_text="$(hyprctl monitors 2>/dev/null | awk '
      $1 == "Monitor" {mon=$2}
      /focused: yes/ {print mon; exit}
    ')"
    if [[ -n "$focused_text" ]]; then
      printf "%s\n" "$focused_text"
      return 0
    fi
  fi

  printf "%s\n" "eDP-1"
}

wait_for_tailscale_ip() {
  local attempt=1
  local max_attempts=12
  local ip=""

  while (( attempt <= max_attempts )); do
    ip="$(get_tailscale_ip || true)"
    if [[ -n "$ip" ]]; then
      printf "%s\n" "$ip"
      return 0
    fi

    sleep 0.4
    (( attempt++ ))
  done

  return 1
}

run_service_action() {
  local action="$1"

  if sudo -n true >/dev/null 2>&1; then
    sudo /usr/bin/systemctl "$action" "${system_services[@]}"
    sudo /usr/bin/systemctl disable "${system_services[@]}" >/dev/null 2>&1 || true
    return 0
  fi

  if [[ -t 0 ]] && sudo -v >/dev/null 2>&1; then
    sudo /usr/bin/systemctl "$action" "${system_services[@]}"
    sudo /usr/bin/systemctl disable "${system_services[@]}" >/dev/null 2>&1 || true
    return 0
  fi

  if command -v pkexec >/dev/null 2>&1; then
    pkexec /bin/sh -c "/usr/bin/systemctl ${action} tailscaled; /usr/bin/systemctl disable tailscaled >/dev/null 2>&1 || true"
    return 0
  fi

  notify "Remote services" "Need sudo/pkexec privileges to change services"
  return 1
}

is_wayvnc_active() {
  if [[ -f "$wayvnc_pid_file" ]]; then
    local pid
    pid="$(cat "$wayvnc_pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    rm -f "$wayvnc_pid_file"
  fi

  pgrep -x wayvnc >/dev/null 2>&1
}

start_wayvnc() {
  if is_wayvnc_active; then
    return 0
  fi

  local bind_ip
  if ! bind_ip="$(wait_for_tailscale_ip)"; then
    notify "Remote services" "tailscaled started but no Tailscale IP available"
    return 1
  fi

  local selected_output
  selected_output="$(detect_focused_output)"

  local wayvnc_args=()
  if [[ "$wayvnc_use_gpu" == "1" ]]; then
    wayvnc_args+=(-g)
  fi

  wayvnc "${wayvnc_args[@]}" -o "$selected_output" "$bind_ip" "$wayvnc_port" >"$wayvnc_log_file" 2>&1 &
  echo "$!" > "$wayvnc_pid_file"

  sleep 0.2
  if ! is_wayvnc_active; then
    notify "Remote services" "wayvnc failed to start (check $wayvnc_log_file)"
    return 1
  fi

  notify "Remote services" "wayvnc capturing output: $selected_output"

  return 0
}

stop_wayvnc() {
  if [[ -f "$wayvnc_pid_file" ]]; then
    local pid
    pid="$(cat "$wayvnc_pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$wayvnc_pid_file"
  fi

  pkill -x wayvnc >/dev/null 2>&1 || true
}

launch_dashboard() {
  if [[ ! -x "$dashboard_script" ]]; then
    return 0
  fi

  if [[ -t 0 && -t 1 ]]; then
    "$dashboard_script"
    return 0
  fi

  if command -v kitty >/dev/null 2>&1; then
    kitty --title "Remote Services Dashboard" "$dashboard_script" >/dev/null 2>&1 &
    return 0
  fi

  if command -v foot >/dev/null 2>&1; then
    foot "$dashboard_script" >/dev/null 2>&1 &
    return 0
  fi

  if command -v alacritty >/dev/null 2>&1; then
    alacritty -t "Remote Services Dashboard" -e "$dashboard_script" >/dev/null 2>&1 &
    return 0
  fi

  if command -v wezterm >/dev/null 2>&1; then
    wezterm start --always-new-process "$dashboard_script" >/dev/null 2>&1 &
    return 0
  fi

  if command -v konsole >/dev/null 2>&1; then
    konsole -e "$dashboard_script" >/dev/null 2>&1 &
    return 0
  fi

  if command -v xterm >/dev/null 2>&1; then
    xterm -T "Remote Services Dashboard" -e "$dashboard_script" >/dev/null 2>&1 &
    return 0
  fi

  notify "Remote services" "No supported terminal found for dashboard"
}

start_inhibitor() {
  if [[ -f "$inhibitor_pid_file" ]]; then
    local existing_pid
    existing_pid="$(cat "$inhibitor_pid_file" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      return 0
    fi
    rm -f "$inhibitor_pid_file"
  fi

  systemd-inhibit \
    --what=sleep:idle:handle-lid-switch \
    --mode=block \
    --who="Hyprland Remote Toggle" \
    --why="$inhibitor_reason" \
    bash -lc 'while true; do sleep 3600; done' \
    >/dev/null 2>&1 &

  echo "$!" > "$inhibitor_pid_file"
}

stop_inhibitor() {
  if [[ ! -f "$inhibitor_pid_file" ]]; then
    return 0
  fi

  local inhibitor_pid
  inhibitor_pid="$(cat "$inhibitor_pid_file" 2>/dev/null || true)"
  if [[ -n "$inhibitor_pid" ]] && kill -0 "$inhibitor_pid" 2>/dev/null; then
    kill "$inhibitor_pid" 2>/dev/null || true
  fi

  rm -f "$inhibitor_pid_file"
}

for service in "${system_services[@]}"; do
  if ! systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}' | grep -qx "${service}.service"; then
    notify "Remote services" "Missing service: $service"
    exit 1
  fi
done

all_on=false
if systemctl is-active --quiet tailscaled && is_wayvnc_active; then
  all_on=true
fi

if [[ "$mode" == "start" ]]; then
  action="start"
elif [[ "$mode" == "stop" ]]; then
  action="stop"
elif $all_on; then
  action="stop"
else
  action="start"
fi

if [[ "$action" == "start" ]]; then
  if ! run_service_action start; then
    exit 1
  fi

  start_inhibitor
  if ! start_wayvnc; then
    stop_inhibitor
    exit 1
  fi

  bind_ip="$(get_tailscale_ip || true)"
  notify "Remote services" "tailscaled + wayvnc started; sleep blocked; target ${bind_ip:-unknown}:${wayvnc_port}"

  if $open_dashboard; then
    launch_dashboard
  fi
else
  stop_wayvnc
  stop_inhibitor

  if ! run_service_action stop; then
    exit 1
  fi

  notify "Remote services" "tailscaled + wayvnc stopped; normal sleep restored"
fi
