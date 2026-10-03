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
| `https://<host>.ts.net` | [Dashboard](../dashboard/README.md): services with start/stop, live graphs, processes, sessions, devices, commands, docs |
| `https://<host>.ts.net:8444` | VS Code in the browser (code-server) |
| `https://<host>.ts.net:10000` | Full desktop in the browser (Moonlight Web) |
| `https://<host>.ts.net:8445` | Terminal in the browser (ttyd → your tmux sessions) |
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

## Web terminal

`https://<host>.ts.net:8445` runs `t`, so it opens the same tmux sessions as kitty and SSH.

- Font and colors match kitty (JetBrains Mono Nerd Font, served by the page).
- **Images:** paste (Cmd+V) or drop an image; it is saved on the laptop and its path is
  typed in. Claude Code attaches an image when you paste its path. Saved under
  `~/.cache/web-paste/`, private, deleted after 7 days.
- **Copy:** select with the mouse or tmux copy mode and it lands in your local clipboard
  (OSC 52). Option+drag makes a plain browser selection.
- Option works as Alt (tmux prefix `Option+A`).

Over plain SSH from a Mac, add this to `~/.zshrc` to send a clipboard image:

```bash
limg() {  # send the clipboard image to the laptop; copies its path for Cmd+V
  local f="/tmp/clip-$(date +%s).png"
  osascript -e "set f to open for access POSIX file \"$f\" with write permission" \
            -e 'write (the clipboard as «class PNGf») to f' -e 'close access f' || return
  scp -q "$f" <user>@<host>:.cache/web-paste/ && rm "$f" &&
  printf '/home/<user>/.cache/web-paste/%s' "$(basename "$f")" | pbcopy &&
  echo "Image sent: Cmd+V pastes its path"
}
```

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

## Ports

| Port | Bound to | Exposed as |
|---|---|---|
| 8080 | code-server | `:8444` (tailnet) |
| 8090 | Moonlight Web | `:10000` (tailnet) |
| 7681 | ttyd | `:8445` (tailnet) |
| 8095 | dashboard API | `/api` on `:443` and `:8445` (tailnet) |
| 47984–48010 | Sunshine | Tailscale interface only (firewall) |
| 40000–40100/udp | Moonlight Web WebRTC | Tailscale interface only |
| any | `demo PORT` | `:8443` (**public**, while running) |

## Performance

The remote stack is built to cost almost nothing when you aren't using it:

- **Dashboard API:** samples every 2 s (with a process scan) only while a dashboard is
  open; otherwise every 30 s without one (~0.05% of a core).
- **NVIDIA GPU** is only queried when already awake and watched, so it can stay in
  runtime suspend (`nvidia-smi` would wake it).
- **Priorities:** background services run with lower CPU/IO weight and soft memory caps
  (`MemoryHigh`), so they yield to the desktop. tmux and Sunshine keep normal priority.
- **Logs:** ttyd and Moonlight Web log warnings only; the journal is capped at 500 MB.
- **Stop what you don't use** from the dashboard; `remote-off` stops everything.

## Keeping the repo in sync

```bash
./scripts/sync-from-system.sh   # copy live setup into the repo, template personal values
git diff && git commit -am "..." && git push
```

`sync-from-system.sh` replaces personal values with `__HOME__`, `__TS_HOST__`,
`__TS_IP__`, `__TS_USER__` and `__MAC_HOST__` (rendered back by `install.sh`), never
copies credentials, and runs `scripts/check-secrets.sh` on the result. Put your real
secret strings in `local.secrets` (gitignored) so the check can catch them exactly.
