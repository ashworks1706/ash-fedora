#!/usr/bin/env bash
# Set up remote access from a Mac/iPhone over Tailscale (needs sudo; safe to rerun):
#   Tailscale (+SSH, Taildrop) · Sunshine (Moonlight) on the AMD iGPU encoder ·
#   code-server (VS Code in the browser) · Moonlight Web (desktop in the browser) ·
#   dashboard with start/stop · tmux sessions that survive logouts and reboots.
# Run scripts/install.sh first (configs, units, scripts), then this.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARE="$HOME/.local/share"
step() { printf '\n\e[1;36m==> %s\e[0m\n' "$*"; }

step "1. Packages: Tailscale, Sunshine, AMD video encoder, Remmina"
if ! rpm -q tailscale >/dev/null; then
  sudo dnf config-manager addrepo --overwrite --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
fi
sudo dnf copr enable -y lizardbyte/stable
# Hybrid G14: the screen is drawn on the AMD iGPU, so Sunshine encodes there (VAAPI).
# Fedora's Mesa omits H.264/HEVC encoding; RPM Fusion's freeworld build adds it.
sudo dnf install -y tailscale Sunshine mesa-va-drivers-freeworld libva-utils jq ttyd nodejs-npm python3-psutil remmina remmina-plugins-vnc

step "2. code-server (VS Code in the browser)"
if ! command -v code-server >/dev/null; then
  url=$(curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest \
        | jq -r '.assets[] | select(.name|test("amd64.rpm$")) | .browser_download_url')
  tmp=$(mktemp -d); curl -fsSL -o "$tmp/code-server.rpm" "$url"
  sudo dnf install -y --nogpgcheck "$tmp/code-server.rpm"   # upstream doesn't sign its RPMs
  rm -rf "$tmp"
fi

step "3. Moonlight Web (desktop in the browser), checksum-verified"
if [[ ! -x "$SHARE/moonlight-web/package/web-server" ]]; then
  rel=$(curl -fsSL https://api.github.com/repos/MrCreativ3001/moonlight-web-stream/releases/latest)
  asset=$(jq -c '.assets[] | select(.name=="moonlight-web-x86_64-unknown-linux-gnu.tar.gz")' <<<"$rel")
  mkdir -p "$SHARE/moonlight-web"; cd "$SHARE/moonlight-web"
  curl -fsSL -o mw.tar.gz "$(jq -r .browser_download_url <<<"$asset")"
  echo "$(jq -r '.digest | sub("^sha256:";"")' <<<"$asset")  mw.tar.gz" | sha256sum -c -
  tar xzf mw.tar.gz && rm mw.tar.gz && chmod +x package/web-server package/streamer
  cd "$REPO_ROOT"
fi

step "3b. Web terminal: JetBrains Mono Nerd Font (also kitty's font) and page"
fonts="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
if [[ ! -f "$fonts/JetBrainsMonoNerdFontMono-Regular.ttf" ]]; then
  rel=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest)
  asset=$(jq -c '.assets[] | select(.name=="JetBrainsMono.tar.xz")' <<<"$rel")
  tmp=$(mktemp -d); curl -fsSL -o "$tmp/jbm.tar.xz" "$(jq -r .browser_download_url <<<"$asset")"
  echo "$(jq -r '.digest | sub("^sha256:";"")' <<<"$asset")  $tmp/jbm.tar.xz" | sha256sum -c -
  mkdir -p "$fonts" && tar xJf "$tmp/jbm.tar.xz" -C "$fonts" --wildcards '*.ttf' && rm -rf "$tmp"
  fc-cache -f "$fonts" >/dev/null
fi
mkdir -p "$SHARE/web-terminal/fonts"
cp "$fonts"/JetBrainsMonoNerdFontMono-{Regular,Bold,Italic}.ttf "$SHARE/web-terminal/fonts/"
"$SHARE/web-terminal/make-index.sh"

step "4. Tailscale: on at boot, SSH on, $USER as operator"
sudo systemctl enable --now tailscaled
sleep 2
if [[ "$(tailscale status --json 2>/dev/null | jq -r .BackendState)" == "Running" ]]; then
  sudo tailscale set --ssh --operator="$USER"
else
  echo "Sign in with the URL below:"
  sudo tailscale up --ssh --operator="$USER"
fi

step "5. Firewall: Sunshine/Moonlight reachable over Tailscale only"
sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0
default_zone=$(firewall-cmd --get-default-zone)
for proto in tcp udp; do
  sudo firewall-cmd --permanent --zone="$default_zone" \
    --add-rich-rule="rule port port=\"47984-48010\" protocol=\"$proto\" reject" 2>/dev/null || true
done
sudo firewall-cmd --reload

step "6. Keep user services running while logged out"
sudo loginctl enable-linger "$USER"
systemctl --user daemon-reload
systemctl --user enable --now tmux.service

step "7. Render Tailscale placeholders now that it's up, then start everything"
"$REPO_ROOT/scripts/install.sh" >/dev/null
"$HOME/.local/bin/remote-on"

echo
echo "Done. Next:"
echo "  - Open the dashboard from any Tailscale device: https://$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')"
echo "  - Tailscale admin: turn on Serve/Funnel and HTTPS certificates if prompted"
echo "  - Sunshine web UI (pair Moonlight/Moonlight Web): https://localhost:47990"
echo "  - Optional: scripts/install-system.sh (lid stays awake on AC, auto-login to a locked desktop)"
