# ash-fedora

Open, reproducible Hyprland + Quickshell setup for Fedora (ASUS G14-friendly baseline).

## What is included

- Hyprland config: `config/hypr`
- Quickshell config: `config/quickshell`
- Illogical Impulse options: `config/illogical-impulse/config.json`
- TTY launcher helper: `local-bin/start-hyprland`
- Terminal: kitty (`config/kitty`), tmux (`home/.tmux.conf`) with sessions that survive
  closing kitty, SSH disconnects and reboots
- Remote access from a Mac/iPhone over Tailscale: VS Code and the full desktop in the
  browser, Moonlight, a dashboard, public demo links. See [docs/REMOTE.md](docs/REMOTE.md)
- System tweaks (`system/`): lid stays awake on AC, auto-login to a locked desktop,
  backlight permissions
- Maintenance scripts:
  - `scripts/doctor.sh`
  - `scripts/install.sh`: user configs, units and scripts (no root)
  - `scripts/install-system.sh`: system files (sudo)
  - `scripts/setup-remote.sh`: remote-access packages and services (sudo)
  - `scripts/sync-from-system.sh`: copy the live setup back into the repo
  - `scripts/check-secrets.sh`: block credentials from being committed
  - `scripts/uninstall.sh`

## Safety defaults

- Personal paths are templated with `__HOME__` and rendered during install.
- Tailscale names, IP and login are templated (`__TS_HOST__`, `__TS_IP__`, `__TS_USER__`,
  `__MAC_HOST__`) and filled in from `tailscale status` / `local.env` at install.
- Credentials are never committed: code-server's password is generated per machine,
  Sunshine pairings and Google Calendar tokens stay local, and `check-secrets.sh` runs
  on every sync.
- GitHub sidebar widget is disabled by default.
- No API tokens are stored in this repo.
- Token path (if you enable GitHub widget later):
  - `~/.config/quickshell/ii/secrets/github_token`

## Install

```bash
git clone https://github.com/ashworks1706/ash-fedora.git
cd ash-fedora
./scripts/doctor.sh
./scripts/install.sh
```

Then reload:

```bash
hyprctl reload
pkill -USR1 quickshell 2>/dev/null || true
```

## Uninstall / rollback

```bash
./scripts/uninstall.sh --restore-latest
```

Backups are kept under:

- `~/.local/state/hypr-fedora-oss/backups/<timestamp>/`

## Enable GitHub contribution widget (optional)

1. Create token file:
   - `mkdir -p ~/.config/quickshell/ii/secrets`
   - `chmod 700 ~/.config/quickshell/ii/secrets`
   - `printf '%s\n' '<your-token>' > ~/.config/quickshell/ii/secrets/github_token`
   - `chmod 600 ~/.config/quickshell/ii/secrets/github_token`
2. Edit:
   - `~/.config/illogical-impulse/config.json`
3. In `sidebar.github` set:
   - `"enable": true`
   - `"username": "<your-github-username>"`

## Notes

- This repo is intentionally user-space only.
- Keep machine-specific tweaks in a private branch if needed.
- See `docs/DEPENDENCIES.md` and `docs/TROUBLESHOOTING.md`.
