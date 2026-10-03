#!/usr/bin/env bash
# Health check: dependencies, unresolved placeholders, secrets permissions, and (if set
# up) the remote-access services. Exits non-zero on problems; remote checks only warn.
set -uo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
errors=0
warnings=0

ok()   { echo "[ok] $*"; }
miss() { echo "[missing] $*"; errors=$((errors + 1)); }
warn() { echo "[warn] $*"; warnings=$((warnings + 1)); }

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then ok "$1"; else miss "$1${2:+ ($2)}"; fi
}

echo "Core tools"
check_cmd Hyprland
check_cmd hyprctl
check_cmd quickshell "quickshell-git COPR"
check_cmd kitty
check_cmd tmux
check_cmd fish
check_cmd jq
check_cmd rsync
check_cmd nmcli
check_cmd secret-tool

echo
echo "Fonts"
if fc-match -f '%{family}' 'JetBrains Mono Nerd Font' 2>/dev/null | grep -qi 'jetbrains'; then
  ok "JetBrains Mono Nerd Font"
else
  warn "JetBrains Mono Nerd Font not installed (kitty falls back; setup-remote.sh installs it)"
fi

echo
echo "Unresolved placeholders in installed files"
targets=("$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/illogical-impulse" "$XDG_CONFIG_HOME/systemd/user"
         "$XDG_CONFIG_HOME/kitty" "$HOME/.tmux.conf" "$HOME/.local/share/dashboard-api" "$HOME/.local/share/web-terminal")
for bin in "$(dirname "${BASH_SOURCE[0]}")"/../local-bin/*; do targets+=("$HOME/.local/bin/$(basename "$bin")"); done
if found=$(grep -rlIE '__(HOME|TS_HOST|TS_IP|TS_USER|MAC_HOST)__' "${targets[@]}" 2>/dev/null); [[ -n "$found" ]]; then
  warn "placeholders left (rerun install.sh after Tailscale is up / local.env is set):"
  echo "$found" | sed "s|$HOME|~|; s|^|       |"
else
  ok "none"
fi

echo
echo "Secrets"
token_file="$XDG_CONFIG_HOME/quickshell/ii/secrets/github_token"
if [[ -f "$token_file" ]]; then
  perms="$(stat -c '%a' "$token_file")"
  [[ "$perms" == "600" ]] && ok "GitHub token is chmod 600" || warn "$token_file should be chmod 600 (is $perms)"
else
  echo "[info] no GitHub token (fine unless the widget is enabled)"
fi
cs="$XDG_CONFIG_HOME/code-server/config.yaml"
if [[ -f "$cs" ]]; then
  [[ "$(stat -c '%a' "$cs")" == "600" ]] && ok "code-server config is chmod 600" || warn "$cs should be chmod 600"
fi

if command -v tailscale >/dev/null 2>&1; then
  echo
  echo "Remote access"
  state="$(tailscale status --json 2>/dev/null | jq -r .BackendState 2>/dev/null)"
  [[ "$state" == "Running" ]] && ok "Tailscale running" || warn "Tailscale is ${state:-not running} (remote-on)"
  [[ -e "$HOME/.config/remote-off" ]] && echo "[info] remote-off is active (remote-on to restore)"
  for unit in tmux dashboard-api web-terminal taildrop-receive code-server moonlight-web llama-swap ntfy; do
    if systemctl --user is-active --quiet "$unit"; then
      ok "$unit"
    elif systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
      warn "$unit is enabled but not running (start it from the dashboard or systemctl --user start $unit)"
    else
      echo "[info] $unit not enabled"
    fi
  done
  pgrep -x sunshine >/dev/null && ok "sunshine" || echo "[info] sunshine not running (starts with Hyprland)"
fi

echo
if [[ "$errors" -gt 0 ]]; then
  echo "Doctor finished with $errors problem(s) and $warnings warning(s)."
  exit 1
fi
[[ "$warnings" -gt 0 ]] && echo "Doctor finished clean ($warnings warning(s))." || echo "Doctor finished clean."
