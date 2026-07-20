#!/usr/bin/env bash
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-fedora-oss"
BACKUPS_DIR="$STATE_DIR/backups"

restore_latest() {
  local latest
  latest="$(ls -1dt "$BACKUPS_DIR"/* 2>/dev/null | head -n1 || true)"
  if [[ -z "${latest:-}" ]]; then
    echo "No backup found in $BACKUPS_DIR"
    exit 1
  fi

  echo "Restoring from backup: $latest"
  if [[ -d "$latest/config/hypr" ]]; then
    rm -rf "$XDG_CONFIG_HOME/hypr"
    rsync -a "$latest/config/hypr/" "$XDG_CONFIG_HOME/hypr/"
  fi
  if [[ -d "$latest/config/quickshell" ]]; then
    rm -rf "$XDG_CONFIG_HOME/quickshell"
    rsync -a "$latest/config/quickshell/" "$XDG_CONFIG_HOME/quickshell/"
  fi
  if [[ -d "$latest/config/illogical-impulse" ]]; then
    rm -rf "$XDG_CONFIG_HOME/illogical-impulse"
    rsync -a "$latest/config/illogical-impulse/" "$XDG_CONFIG_HOME/illogical-impulse/"
  fi
  if [[ -f "$latest/local-bin/start-hyprland/start-hyprland" ]]; then
    install -m 0755 "$latest/local-bin/start-hyprland/start-hyprland" "$LOCAL_BIN/start-hyprland"
  fi
  echo "Restore completed."
}

if [[ "${1:-}" == "--restore-latest" ]]; then
  restore_latest
else
  cat <<'EOF'
No action taken.
Use:
  ./scripts/uninstall.sh --restore-latest
to restore from the most recent backup.
EOF
fi
