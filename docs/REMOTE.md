# Remote access (Mac / iPhone → this laptop)

Everything runs on the laptop and is reachable only from your own Tailscale
devices, except a public `demo` link, which exists only while you run it.

## Setup

```bash
./scripts/install.sh          # configs, units, scripts (no root)
./scripts/setup-remote.sh     # packages, Tailscale, firewall, services (sudo)
./scripts/install-system.sh   # optional: lid awake on AC, auto-login to a locked desktop
```

In the Tailscale admin console, allow Serve/Funnel and HTTPS certificates if prompted.
Pair Moonlight (iPhone app) and Moonlight Web once via Sunshine's web UI at
`https://localhost:47990` (PIN tab) on the laptop.

## What you get

| Address (tailnet only) | What |
|---|---|
| `https://<host>.ts.net` | Dashboard: status, start/stop, dev-server preview, copyable commands |
| `https://<host>.ts.net:8444` | VS Code in the browser (code-server) |
| `https://<host>.ts.net:10000` | Full desktop in the browser (Moonlight Web) |
| `http://<host>:PORT` | A dev server started with `--host` / `-H 0.0.0.0` |
| Moonlight app → `<host>` | Full desktop, lowest latency |
| `ssh -t <user>@<host> t` | Pick a tmux session (same ones as on the laptop) |
| `https://<host>.ts.net:8443` | **Public** link while `demo PORT` runs |

## Commands (installed to `~/.local/bin`)

| Command | Does |
|---|---|
| `t [NAME]` | Attach to a tmux session picker, or session NAME |
| `demo PORT` | Share `localhost:PORT` publicly over HTTPS until Ctrl+C |
| `remote-off` / `remote-on` | Turn all remote access off (stays off) / back on |
| `kitty-tmux` | kitty's shell: reattach to a free tmux session |

## How it fits together

- **Tailscale** (system service) carries everything: SSH, Taildrop, `serve` for HTTPS.
- **tmux** runs as `tmux.service`, not inside a login, so SSH disconnects and closing
  kitty never kill sessions; tmux-continuum restores them at boot.
- **Sunshine** starts with Hyprland and encodes on the **AMD iGPU (VAAPI)**: on this
  hybrid G14 the screen is drawn there, and NVENC can't import those frames.
- **Firewall:** `tailscale0` is trusted; Sunshine's ports are rejected on other networks.
- **Dashboard API** (`share/dashboard-api/server.py`) only accepts the tailnet owner's
  identity (from `tailscale serve`) and only whitelisted start/stop actions.
- **Power:** lid closed on AC stays awake; on battery it suspends as usual.

## Keeping the repo in sync

```bash
./scripts/sync-from-system.sh   # copy live setup into the repo, template personal values
git diff && git commit -am "..." && git push
```

`sync-from-system.sh` replaces personal values with `__HOME__`, `__TS_HOST__`,
`__TS_IP__`, `__TS_USER__` and `__MAC_HOST__` (rendered back by `install.sh`), never
copies credentials, and runs `scripts/check-secrets.sh` on the result. Put your real
secret strings in `local.secrets` (gitignored) so the check can catch them exactly.
