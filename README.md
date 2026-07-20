# ash-fedora

Open, reproducible Hyprland + Quickshell setup for Fedora (ASUS G14-friendly baseline).

## What is included

- Hyprland config: `config/hypr`
- Quickshell config: `config/quickshell`
- Illogical Impulse options: `config/illogical-impulse/config.json`
- TTY launcher helper: `local-bin/start-hyprland`
- Maintenance scripts:
  - `scripts/doctor.sh`
  - `scripts/install.sh`
  - `scripts/uninstall.sh`

## Safety defaults

- Personal paths are templated with `__HOME__` and rendered during install.
- GitHub sidebar widget is disabled by default.
- No API tokens are stored in this repo.
- Token path (if you enable GitHub widget later):
  - `~/.config/quickshell/ii/secrets/github_token`

## Install

```bash
git clone https://github.com/<you>/hypr-fedora-oss.git
cd hypr-fedora-oss
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
