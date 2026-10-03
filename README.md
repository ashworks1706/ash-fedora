# ash-fedora

A reproducible Fedora workstation setup for an ASUS ROG Zephyrus G14 (Ryzen + NVIDIA
hybrid graphics): a Hyprland + Quickshell desktop, a terminal with sessions that never
die, and private remote access from a Mac or iPhone over Tailscale, with a dashboard to
run it all from.

Everything installs into your home directory with backups first; system tweaks and
remote-access packages are separate, opt-in steps.

## What you get

| Area | Highlights |
|---|---|
| **Desktop** | Hyprland + [Quickshell `ii`](config/quickshell) bar and widgets, cheatsheet on `Super+/`, custom keybinds |
| **Terminal** | kitty + tmux: every window is a tmux session that survives closing kitty, SSH drops and reboots |
| **Remote access** | Over Tailscale, from anywhere: VS Code, a terminal and the full desktop **in the browser**, Moonlight streaming, SSH, file sending, public demo links. [Guide](docs/REMOTE.md) |
| **Dashboard** | A Next.js home page for the machine: services with start/stop, live CPU/GPU/memory/network/thermal graphs, processes, sessions, devices. [Details](dashboard/README.md) |
| **Laptop tweaks** | Lid closed on AC stays awake, auto-login to a locked desktop, backlight fix, journal cap |
| **Tooling** | Installer with backups and rollback, health check, one-command sync back into this repo with secret scanning |

## Quick start

```bash
git clone https://github.com/ashworks1706/ash-fedora.git && cd ash-fedora
./scripts/doctor.sh            # check dependencies
./scripts/install.sh           # desktop, terminal, scripts (no root; backs up first)
hyprctl reload
```

Optional:

```bash
./scripts/setup-remote.sh      # remote access: Tailscale, Sunshine, code-server, dashboard (sudo)
./scripts/install-system.sh    # laptop tweaks (sudo; --no-autologin to skip auto-login)
```

Undo: `./scripts/uninstall.sh --restore-latest` restores the most recent backup from
`~/.local/state/hypr-fedora-oss/backups/`.

## Repository layout

Folders mirror where files live on the machine.

```
config/              → ~/.config
  hypr/                Hyprland (custom/ holds personal keybinds, execs, rules)
  quickshell/          Quickshell "ii" shell (bar, sidebars, cheatsheet, lock screen)
  illogical-impulse/   ii options (config.json only; credentials stay local)
  kitty/  fish/        terminal and login-shell snippets
  systemd/user/        user services: tmux, dashboard API, web terminal, Moonlight Web, Taildrop
  sunshine/            stream host settings (AMD VAAPI encoder)
  code-server/         config template (password generated per machine)
home/.tmux.conf      → ~/.tmux.conf
local-bin/           → ~/.local/bin      t, kitty-tmux, demo, remote-on/off, start-hyprland, …
share/               → ~/.local/share    dashboard API, web terminal page and launcher
system/              → /                 lid, auto-login, backlight, journald (install-system.sh)
dashboard/             Next.js dashboard source (built by scripts/build-dashboard.sh)
scripts/               install, setup, sync, health check, secret check, uninstall
docs/                  guides
```

## Docs

| Doc | For |
|---|---|
| [docs/REMOTE.md](docs/REMOTE.md) | Remote access: addresses, commands, how the pieces fit, performance |
| [dashboard/README.md](dashboard/README.md) | Dashboard: build, develop, API reference |
| [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) | Packages each part needs |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Known problems and fixes |
| [SECURITY.md](SECURITY.md) | What is exposed, and how secrets are kept out of the repo |

## Keeping the repo in sync

Edit your live setup as usual, then:

```bash
./scripts/sync-from-system.sh   # copy it in, template personal values, scan for secrets
git diff                        # review
git commit -am "…" && git push
```

Personal values become placeholders (`__HOME__`, `__TS_HOST__`, `__TS_IP__`, `__TS_USER__`,
`__MAC_HOST__`) that `install.sh` fills back in from your environment, `tailscale status`
and `local.env`. Credentials are never copied, and the sync fails if anything that looks
like one slips through.

## Optional: GitHub contribution widget

```bash
mkdir -p ~/.config/quickshell/ii/secrets && chmod 700 ~/.config/quickshell/ii/secrets
printf '%s\n' '<token>' > ~/.config/quickshell/ii/secrets/github_token
chmod 600 ~/.config/quickshell/ii/secrets/github_token
```

Then set `sidebar.github.enable` and `sidebar.github.username` in
`~/.config/illogical-impulse/config.json`.

## License

[MIT](LICENSE)
