#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-fedora-oss"
BACKUP_DIR="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR" "$LOCAL_BIN" "$STATE_DIR"

backup_path() {
  local src="$1"
  local name="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$BACKUP_DIR/$name"
    rsync -a "$src" "$BACKUP_DIR/$name/"
  fi
}

echo "[1/4] Backing up existing configs to: $BACKUP_DIR"
backup_path "$XDG_CONFIG_HOME/hypr" "config"
backup_path "$XDG_CONFIG_HOME/quickshell" "config"
backup_path "$XDG_CONFIG_HOME/illogical-impulse" "config"
backup_path "$LOCAL_BIN/start-hyprland" "local-bin"

echo "[2/4] Installing configs"
mkdir -p "$XDG_CONFIG_HOME"
rsync -a "$REPO_ROOT/config/hypr/" "$XDG_CONFIG_HOME/hypr/"
rsync -a "$REPO_ROOT/config/quickshell/" "$XDG_CONFIG_HOME/quickshell/"
mkdir -p "$XDG_CONFIG_HOME/illogical-impulse"
install -m 0644 "$REPO_ROOT/config/illogical-impulse/config.json" "$XDG_CONFIG_HOME/illogical-impulse/config.json"

echo "[3/4] Installing launcher helper"
install -m 0755 "$REPO_ROOT/local-bin/start-hyprland" "$LOCAL_BIN/start-hyprland"

echo "[4/4] Rendering local placeholders"
find "$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/illogical-impulse" -type f \
  \( -name "*.conf" -o -name "*.json" -o -name "*.sh" \) -print0 \
  | xargs -0 sed -i "s|__HOME__|$HOME|g"

mkdir -p "$XDG_CONFIG_HOME/quickshell/ii/secrets"
chmod 700 "$XDG_CONFIG_HOME/quickshell/ii/secrets"

cat > "$STATE_DIR/last-install.txt" <<EOF
repo=$REPO_ROOT
installed_at=$(date -Is)
backup=$BACKUP_DIR
EOF

echo "Install complete."
echo "Reload with: hyprctl reload && pkill -USR1 quickshell 2>/dev/null || true"
