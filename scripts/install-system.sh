#!/usr/bin/env bash
# Install the system-level pieces (needs sudo):
#   - lid: stay awake when closed on AC power (suspend on battery)
#   - tty1 auto-login -> Hyprland, locked immediately (skip with --no-autologin)
#   - backlight permissions fix for the active backlight device
#   - cap the system journal at 500M
# Takes effect at next boot; nothing running is restarted.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYS="$REPO_ROOT/system"
autologin=1
[[ "${1:-}" == "--no-autologin" ]] && autologin=0

sudo install -D -m 0644 "$SYS/etc/systemd/journald.conf.d/size.conf" /etc/systemd/journald.conf.d/size.conf
sudo install -D -m 0644 "$SYS/etc/systemd/logind.conf.d/fix-lid.conf" /etc/systemd/logind.conf.d/fix-lid.conf
sudo install -D -m 0755 "$SYS/usr/local/bin/fix-backlight-permissions" /usr/local/bin/fix-backlight-permissions
sudo install -D -m 0644 "$SYS/etc/systemd/system/fix-backlight.service" /etc/systemd/system/fix-backlight.service

if [[ $autologin -eq 1 ]]; then
  # The repo copy auto-logs in "ash"; use whoever runs this.
  sed "s/--autologin ash /--autologin $USER /" \
    "$SYS/etc/systemd/system/getty@tty1.service.d/autologin.conf" \
    | sudo install -D -m 0644 /dev/stdin /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "Auto-login on tty1 enabled for $USER (Hyprland starts locked)."
else
  echo "Skipped auto-login."
fi

sudo systemctl daemon-reload
sudo systemctl enable fix-backlight.service
sudo systemctl restart systemd-journald
sudo systemctl kill -s HUP systemd-logind   # reload lid settings without ending sessions
echo "System files installed. Auto-login applies from the next boot."
