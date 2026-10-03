#!/usr/bin/env bash
# Install this setup into the current user's home (no root needed).
# System files and remote-access packages are separate:
#   scripts/install-system.sh   (sudo: lid/auto-login/backlight)
#   scripts/setup-remote.sh     (sudo: Tailscale, Sunshine, code-server, Moonlight Web)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share"
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

# Single files are backed up under files/<path relative to $HOME>.
backup_file() {
  local src="$1" rel="${1#"$HOME"/}"
  if [[ -e "$src" ]]; then
    mkdir -p "$BACKUP_DIR/files/$(dirname "$rel")"
    cp -a "$src" "$BACKUP_DIR/files/$rel"
  fi
}

# Files installed outside the three config trees: repo path -> destination.
declare -A FILES=(
  [config/kitty/kitty.conf]="$XDG_CONFIG_HOME/kitty/kitty.conf"
  [config/fish/conf.d/hyprland-autostart.fish]="$XDG_CONFIG_HOME/fish/conf.d/hyprland-autostart.fish"
  [home/.tmux.conf]="$HOME/.tmux.conf"
  [config/systemd/user/code-server.service.d/priority.conf]="$XDG_CONFIG_HOME/systemd/user/code-server.service.d/priority.conf"
  [config/llm/llama-swap.yaml]="$XDG_CONFIG_HOME/llm/llama-swap.yaml"
  [config/sunshine/sunshine.conf]="$XDG_CONFIG_HOME/sunshine/sunshine.conf"
  [config/sunshine/apps.json]="$XDG_CONFIG_HOME/sunshine/apps.json"
  [share/dashboard-api/server.py]="$SHARE/dashboard-api/server.py"
  [share/web-terminal/inject.html]="$SHARE/web-terminal/inject.html"
  [share/web-terminal/make-index.sh]="$SHARE/web-terminal/make-index.sh"
  [share/web-terminal/run.sh]="$SHARE/web-terminal/run.sh"
)
for unit in "$REPO_ROOT"/config/systemd/user/*.service; do
  FILES[config/systemd/user/$(basename "$unit")]="$XDG_CONFIG_HOME/systemd/user/$(basename "$unit")"
done

echo "[1/5] Backing up existing configs to: $BACKUP_DIR"
backup_path "$XDG_CONFIG_HOME/hypr" "config"
backup_path "$XDG_CONFIG_HOME/quickshell" "config"
backup_path "$XDG_CONFIG_HOME/illogical-impulse" "config"
for bin in "$REPO_ROOT"/local-bin/*; do
  backup_path "$LOCAL_BIN/$(basename "$bin")" "local-bin"
done
for rel in "${!FILES[@]}"; do
  backup_file "${FILES[$rel]}"
done

echo "[2/5] Installing configs"
mkdir -p "$XDG_CONFIG_HOME"
rsync -a "$REPO_ROOT/config/hypr/" "$XDG_CONFIG_HOME/hypr/"
rsync -a "$REPO_ROOT/config/quickshell/" "$XDG_CONFIG_HOME/quickshell/"
mkdir -p "$XDG_CONFIG_HOME/illogical-impulse"
install -m 0644 "$REPO_ROOT/config/illogical-impulse/config.json" "$XDG_CONFIG_HOME/illogical-impulse/config.json"
for rel in "${!FILES[@]}"; do
  mode=0644; [[ "$rel" == *.sh ]] && mode=0755
  install -D -m "$mode" "$REPO_ROOT/$rel" "${FILES[$rel]}"
done

# code-server: never overwrite an existing config (it holds the password).
cs_cfg="$XDG_CONFIG_HOME/code-server/config.yaml"
if [[ ! -f "$cs_cfg" ]]; then
  install -D -m 0600 "$REPO_ROOT/config/code-server/config.yaml.template" "$cs_cfg"
  sed -i "s|__GENERATED__|$(python3 -c 'import secrets; print(secrets.token_urlsafe(12))')|" "$cs_cfg"
  echo "  code-server password generated in $cs_cfg"
fi

echo "[3/5] Installing scripts into $LOCAL_BIN"
for bin in "$REPO_ROOT"/local-bin/*; do
  install -m 0755 "$bin" "$LOCAL_BIN/$(basename "$bin")"
done

echo "[4/5] Rendering local placeholders"
TS_HOST="" TS_IP="" TS_USER="" MAC_HOST=""
if command -v tailscale >/dev/null && tailscale status --json >/dev/null 2>&1; then
  ts="$(tailscale status --json)"
  TS_HOST="$(jq -r '.Self.DNSName | rtrimstr(".")' <<<"$ts")"
  TS_IP="$(jq -r '.Self.TailscaleIPs[0]' <<<"$ts")"
  TS_USER="$(jq -r '.User[(.Self.UserID|tostring)].LoginName' <<<"$ts")"
fi
# shellcheck disable=SC1091
[[ -f "$REPO_ROOT/local.env" ]] && source "$REPO_ROOT/local.env"

# Only files this script installed: never other binaries or symlinks in ~/.local/bin.
{
  find "$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/illogical-impulse" -type f \
    \( -name "*.conf" -o -name "*.json" -o -name "*.sh" \) -print0
  for rel in "${!FILES[@]}"; do printf '%s\0' "${FILES[$rel]}"; done
  for bin in "$REPO_ROOT"/local-bin/*; do printf '%s\0' "$LOCAL_BIN/$(basename "$bin")"; done
} | xargs -0 sed -i \
      -e "s|__HOME__|$HOME|g" \
      ${TS_HOST:+-e "s|__TS_HOST__|$TS_HOST|g"} \
      ${TS_IP:+-e "s|__TS_IP__|$TS_IP|g"} \
      ${TS_USER:+-e "s|__TS_USER__|$TS_USER|g"} \
      ${MAC_HOST:+-e "s|__MAC_HOST__|$MAC_HOST|g"}
[[ -z "$TS_HOST" ]] && echo "  Tailscale isn't up: __TS_* placeholders left; rerun after setup-remote.sh"
[[ -z "$MAC_HOST" ]] && echo "  MAC_HOST not set (cp local.env.example local.env): __MAC_HOST__ left in cheatsheet"

mkdir -p "$XDG_CONFIG_HOME/quickshell/ii/secrets"
chmod 700 "$XDG_CONFIG_HOME/quickshell/ii/secrets"

if command -v npm >/dev/null; then
  echo "  building the dashboard (dashboard/)"
  "$REPO_ROOT/scripts/build-dashboard.sh" >/dev/null
else
  echo "  npm not found: skipped the dashboard (scripts/build-dashboard.sh later)"
fi

echo "[5/5] Reloading user services"
systemctl --user daemon-reload 2>/dev/null || true

cat > "$STATE_DIR/last-install.txt" <<EOF
repo=$REPO_ROOT
installed_at=$(date -Is)
backup=$BACKUP_DIR
EOF

echo "Install complete."
echo "Reload with: hyprctl reload && pkill -USR1 quickshell 2>/dev/null || true"
