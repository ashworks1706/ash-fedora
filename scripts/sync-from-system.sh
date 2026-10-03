#!/usr/bin/env bash
# Copy the live setup from this machine into the repo, so it can be committed.
# Personal values are replaced with placeholders (rendered back by install.sh),
# secrets are never copied, and the result is scanned before you commit.
#
#   ./scripts/sync-from-system.sh        then review `git diff` and commit
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
cd "$REPO_ROOT"

# Values to template. Taken from Tailscale when it's running; local.env overrides.
TS_HOST="" TS_IP="" TS_USER="" MAC_HOST=""
if command -v tailscale >/dev/null && tailscale status --json >/dev/null 2>&1; then
  ts="$(tailscale status --json)"
  TS_HOST="$(jq -r '.Self.DNSName | rtrimstr(".")' <<<"$ts")"
  TS_IP="$(jq -r '.Self.TailscaleIPs[0]' <<<"$ts")"
  TS_USER="$(jq -r '.User[(.Self.UserID|tostring)].LoginName' <<<"$ts")"
fi
# shellcheck disable=SC1091
[[ -f local.env ]] && source local.env

copy() {  # copy SRC DEST (file or directory), creating parents
  local src="$1" dest="$2"
  [[ -e "$src" ]] || { echo "  skip (missing): ${src/#$HOME/\~}"; return; }
  mkdir -p "$(dirname "$dest")"
  if [[ -d "$src" ]]; then
    rsync -a --delete \
      --exclude '.venv/' --exclude '__pycache__/' --exclude 'node_modules/' \
      --exclude 'secrets/' --exclude '*.old' --exclude '*backup*' \
      --exclude '.initial_startup_done' \
      "$src/" "$dest/"
  else
    cp -p "$src" "$dest"
  fi
}

echo "[1/4] Desktop configs"
copy "$CFG/hypr"                         config/hypr
copy "$CFG/quickshell"                   config/quickshell
copy "$CFG/illogical-impulse/config.json" config/illogical-impulse/config.json  # never google-calendar/
copy "$CFG/kitty/kitty.conf"             config/kitty/kitty.conf
copy "$CFG/fish/conf.d/hyprland-autostart.fish" config/fish/conf.d/hyprland-autostart.fish
copy "$HOME/.tmux.conf"                  home/.tmux.conf

echo "[2/4] Remote access (Tailscale, Sunshine, code-server, dashboard)"
for unit in tmux moonlight-web dashboard-api taildrop-receive internal-mic-quality web-terminal llama-swap ntfy; do
  copy "$CFG/systemd/user/$unit.service" "config/systemd/user/$unit.service"
done
copy "$CFG/systemd/user/code-server.service.d/priority.conf" config/systemd/user/code-server.service.d/priority.conf
copy "$CFG/ntfy/server.yml"              config/ntfy/server.yml          # not ntfy/env or client.env (secrets)
copy "$CFG/llm/llama-swap.yaml"           config/llm/llama-swap.yaml      # not llm/env (API key)
copy "$CFG/sunshine/sunshine.conf"       config/sunshine/sunshine.conf   # not sunshine_state.json (credentials, pairings)
copy "$CFG/sunshine/apps.json"           config/sunshine/apps.json
copy "$HOME/.local/share/dashboard-api/server.py" share/dashboard-api/server.py
for f in inject.html make-index.sh run.sh; do   # not index.html (built) or fonts (downloaded)
  copy "$HOME/.local/share/web-terminal/$f" "share/web-terminal/$f"
done
# code-server's config.yaml holds the password: only a template lives in the repo.
for bin in start-hyprland kitty-tmux t tmux-server-start demo remote-off remote-on internal-mic-quality notify; do
  copy "$HOME/.local/bin/$bin" "local-bin/$bin"
done

echo "[3/4] System files (installed with scripts/install-system.sh)"
copy /etc/systemd/journald.conf.d/size.conf             system/etc/systemd/journald.conf.d/size.conf
copy /etc/systemd/logind.conf.d/fix-lid.conf              system/etc/systemd/logind.conf.d/fix-lid.conf
copy /etc/systemd/system/getty@tty1.service.d/autologin.conf system/etc/systemd/system/getty@tty1.service.d/autologin.conf
copy /etc/systemd/system/fix-backlight.service            system/etc/systemd/system/fix-backlight.service
copy /usr/local/bin/fix-backlight-permissions             system/usr/local/bin/fix-backlight-permissions

echo "[4/4] Templating personal values"
mapfile -t files < <(git ls-files -co --exclude-standard -- config home local-bin share system)
for f in "${files[@]}"; do
  [[ -L "$f" ]] && continue   # sed -i would replace symlinks with copies
  [[ -f "$f" ]] && grep -Iq . "$f" 2>/dev/null || continue
  sed -i \
    -e "s|$HOME|__HOME__|g" \
    ${TS_HOST:+-e "s|$TS_HOST|__TS_HOST__|g"} \
    ${TS_IP:+-e "s|$TS_IP|__TS_IP__|g"} \
    ${TS_USER:+-e "s|$TS_USER|__TS_USER__|g"} \
    ${MAC_HOST:+-e "s|\\b$MAC_HOST\\b|__MAC_HOST__|g"} \
    "$f"
done

echo
"$REPO_ROOT/scripts/check-secrets.sh"
echo "Synced. Review with: git status && git diff"
