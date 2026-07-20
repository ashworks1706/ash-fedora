#!/usr/bin/env bash
# Toggle laptop panel refresh rate between 60Hz and 165Hz while preserving layout.

set -euo pipefail

# You can override these with env vars if needed
MONITOR="${MONITOR:-eDP-1}"
RESOLUTION="${RESOLUTION:-2560x1600}"
POSITION="${POSITION:-3440x0}"
SCALE="${SCALE:-1.25}"
HIGH_REFRESH="${HIGH_REFRESH:-165}"
LOW_REFRESH="${LOW_REFRESH:-60}"

log() {
  printf "monitor-refresh-rate: %s\n" "$*" >&2
}

normalize_refresh() {
  local raw="$1"

  [[ -z "$raw" || "$raw" == "null" ]] && return 1

  # Hyprland sometimes reports in mHz (e.g., 165000) or as a float (164.99)
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    if (( raw > 1000 )); then
      echo $(( (raw + 500) / 1000 ))
    else
      echo "$raw"
    fi
    return 0
  fi

  # Fallback for decimal values
  printf "%.0f\n" "$raw" 2>/dev/null || return 1
}

current_refresh() {
  command -v hyprctl >/dev/null 2>&1 || {
    log "hyprctl not found"
    return 1
  }

  local raw=""
  if command -v jq >/dev/null 2>&1; then
    raw=$(hyprctl monitors -j 2>/dev/null | jq -r --arg MON "$MONITOR" '
      .[]
      | select(.name==$MON)
      | (.refreshRate // .currentMode.refreshRate // .activeMode.refreshRate // empty)
    ')
  else
    raw=$(hyprctl monitors 2>/dev/null | awk -v mon="$MONITOR" '
      $1 == "Monitor" && $2 == mon {seen=1; next}
      seen && match($0, /@([0-9]+(\.[0-9]+)?)/, m) {print m[1]; exit}
      seen && /refresh rate:/ {gsub(/[^0-9.]/, "", $3); print $3; exit}
      $1 == "Monitor" && $2 != mon && seen {exit}
    ')
  fi

  normalize_refresh "$raw"
}

target_refresh="$HIGH_REFRESH"
if current=$(current_refresh); then
  if (( current >= HIGH_REFRESH - 1 )); then
    target_refresh="$LOW_REFRESH"
  else
    target_refresh="$HIGH_REFRESH"
  fi
fi

if ! hyprctl keyword monitor "$MONITOR,${RESOLUTION}@${target_refresh},${POSITION},${SCALE},vrr,0" >/dev/null 2>&1; then
  log "failed to set ${MONITOR} to ${target_refresh}Hz"
  exit 1
fi

if command -v notify-send >/dev/null 2>&1; then
  current_after="$(current_refresh || true)"
  notify-send -u low "Refresh rate switched" "${MONITOR}: ${target_refresh}Hz (current: ${current_after:-unknown}Hz)"
else
  echo "Set ${MONITOR} to ${target_refresh}Hz"
fi

