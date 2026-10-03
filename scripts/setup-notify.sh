#!/usr/bin/env bash
# Self-hosted push notifications (ntfy) for your phone and browsers, over Tailscale.
# Safe to rerun. Run scripts/install.sh first (config template, unit, `notify` command).
#
# Afterwards: iPhone -> ntfy app -> add server https://<host>.ts.net:8447, sign in,
# subscribe to the topic. Mac -> open that URL in a browser, sign in, subscribe.
set -euo pipefail

NTFY="$HOME/.local/share/ntfy"
CONF="$HOME/.config/ntfy"
TOPIC="${NTFY_TOPIC:-$(hostname -s)}"
step() { printf '\n\e[1;36m==> %s\e[0m\n' "$*"; }

step "1. ntfy server (checksum-verified release)"
if [[ ! -x "$NTFY/bin/ntfy" ]]; then
  rel=$(curl -fsSL https://api.github.com/repos/binwiederhier/ntfy/releases/latest)
  asset=$(jq -c '.assets[] | select(.name|test("linux_amd64.tar.gz$"))' <<<"$rel")
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/ntfy.tgz" "$(jq -r .browser_download_url <<<"$asset")"
  echo "$(jq -r '.digest | sub("^sha256:";"")' <<<"$asset")  $tmp/ntfy.tgz" | sha256sum -c -
  tar xzf "$tmp/ntfy.tgz" -C "$tmp"
  mkdir -p "$NTFY/bin" && cp "$tmp"/ntfy_*_linux_amd64/ntfy "$NTFY/bin/" && rm -rf "$tmp"
fi
mkdir -p "$NTFY/data" "$CONF"

step "2. Browser push keys (private, in $CONF/env)"
if [[ ! -f "$CONF/env" ]]; then
  keys=$("$NTFY/bin/ntfy" webpush keys 2>&1)
  (umask 077; printf 'NTFY_WEB_PUSH_PUBLIC_KEY=%s\nNTFY_WEB_PUSH_PRIVATE_KEY=%s\n' \
    "$(grep -oP 'web-push-public-key:\s*\K\S+' <<<"$keys")" \
    "$(grep -oP 'web-push-private-key:\s*\K\S+' <<<"$keys")" > "$CONF/env")
fi

step "3. Server address from Tailscale"
host=$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')
sed -i "s|__TS_HOST__|$host|g" "$CONF/server.yml"   # if install.sh ran before Tailscale was up

step "4. Service, account and publish token"
systemctl --user daemon-reload
systemctl --user enable --now ntfy.service
sleep 2
if [[ ! -f "$CONF/client.env" ]]; then
  pw=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')
  NTFY_PASSWORD="$pw" "$NTFY/bin/ntfy" user --config "$CONF/server.yml" add --role=admin "$USER"
  tok=$("$NTFY/bin/ntfy" token --config "$CONF/server.yml" add --label "scripts + dashboard" "$USER" | grep -oE 'tk_[A-Za-z0-9]+')
  (umask 077; printf 'NTFY_URL=http://127.0.0.1:2586\nNTFY_TOPIC=%s\nNTFY_TOKEN=%s\n# login for the iPhone app / web app (user: %s)\nNTFY_PASSWORD=%s\n' \
    "$TOPIC" "$tok" "$USER" "$pw" > "$CONF/client.env")
fi
tailscale serve --bg --https=8447 http://127.0.0.1:2586 >/dev/null

step "5. Test"
"$HOME/.local/bin/notify" -t "ntfy is set up" -g white_check_mark "Notifications from $(hostname -s) will arrive here."

echo
echo "Server:   https://$host:8447   topic: $TOPIC   user: $USER"
echo "Password: grep NTFY_PASSWORD $CONF/client.env"
echo "Send:     notify \"message\"   |   notify run <command>"
