#!/usr/bin/env bash
# Launch ttyd for the web terminal (started by web-terminal.service).
# Loopback only: `tailscale serve` exposes it on :8445 and sets Tailscale-User-Login,
# which ttyd requires (--auth-header). --check-origin rejects other sites' websockets.
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
theme='{"background":"#141318","foreground":"#e6e1e8","cursor":"#d0bcff","cursorAccent":"#141318",
"selectionBackground":"#d0bcff","selectionForeground":"#141318",
"black":"#1d1b20","red":"#ffb4ab","green":"#b7f397","yellow":"#e7c872","blue":"#cbbdff",
"magenta":"#efb8c8","cyan":"#a5eeff","white":"#e6e1e8","brightBlack":"#49454f","brightRed":"#ffdad6",
"brightGreen":"#d1ffc0","brightYellow":"#ffe08a","brightBlue":"#e9ddff","brightMagenta":"#ffd8e4",
"brightCyan":"#c2f3ff","brightWhite":"#ffffff"}'
exec /usr/bin/ttyd --interface lo --port 7681 --writable --check-origin \
  --auth-header Tailscale-User-Login \
  --index "$dir/index.html" \
  -t titleFixed=ash-fedora \
  -t fontSize=14 \
  -t 'fontFamily="JBM NF", monospace' \
  -t "theme=${theme//$'\n'/}" \
  -t macOptionIsMeta=true \
  -t macOptionClickForcesSelection=true \
  -t cursorBlink=true \
  -t scrollback=10000 \
  -t disableLeaveAlert=true \
  "$HOME/.local/bin/t"
