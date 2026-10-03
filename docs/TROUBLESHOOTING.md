# Troubleshooting

## Desktop

### Hyprland does not load after config changes

1. Switch to a TTY (`Ctrl+Alt+F2`) and log in.
2. `cd <repo> && ./scripts/uninstall.sh --restore-latest`
3. `start-hyprland`

If auto-login keeps relaunching a broken Hyprland, `touch ~/.no-hypr-autostart` from a
TTY pauses it; delete the file to re-enable.

### The bar (`ii`) is missing or crashes at login

- Check the shell runs: `pgrep -af 'qs -c ii'`; start it with `qs -c ii &`.
- A crash in `FcCharSetHasChar` (see `coredumpctl list quickshell`) is a stale font
  cache: `rm -rf ~/.cache/fontconfig && fc-cache -r`.
- After a Fedora upgrade, check `quickshell` wasn't replaced by a fork
  (`rpm -qf $(command -v qs)`); the `ii` config expects `quickshell-git`.

### Keyring asks for a password

Expected once after a reboot with auto-login (there's no login password to unlock it).
Otherwise make sure the login keyring password matches your user password
(`seahorse` → Login → Change Password).

## Terminal and tmux

### Sessions disappear when SSH disconnects

The tmux server must run as `tmux.service`, not inside a login:
`systemctl --user enable --now tmux.service`. `t` and `kitty-tmux` start it through
systemd; a server started any other way dies with the login that started it.

### Option+A types `å` on the Mac

Make Option act as Meta: Terminal → Settings → Profiles → Keyboard → *Use Option as
Meta key* (iTerm2: Profiles → Keys → Left Option: Esc+). The web terminal does this
already.

## Remote access

### Moonlight: "check your firewall… UDP 47998, 48000"

Usually not the firewall: Sunshine sent no video. On hybrid graphics the screen is drawn
on the AMD iGPU, and NVENC can't import those frames (`Couldn't import RGB Image` in
`~/.config/sunshine/sunshine.log`). Use VAAPI on the iGPU (`config/sunshine/sunshine.conf`)
with `mesa-va-drivers-freeworld` installed.

### Moonlight shows a controller UI instead of the desktop

That's Steam Big Picture. `config/sunshine/apps.json` keeps only *Desktop*.

### Web terminal flashes "Reconnecting…"

The command ttyd runs is failing. Check `journalctl --user -u web-terminal` for
`execvp failed`; the launcher is `~/.local/share/web-terminal/run.sh`.

### A dev server isn't reachable at `http://<host>:PORT`

Start it on all interfaces (`--host`, `-H 0.0.0.0`). Apps that reject other hostnames
(Vite `allowedHosts`, Django `ALLOWED_HOSTS`, FastAPI `TrustedHostMiddleware`) need the
`.ts.net` name allowed, or use a tunnel: `ssh -N -L PORT:localhost:PORT <user>@<host>`.

### VS Code's "Open in Browser" gives a 404

The tab is on an old address; code-server lives at `https://<host>.ts.net:8444`.
Its `/proxy/PORT/` also breaks apps that load assets from `/`; prefer
`http://<host>:PORT`.

### `demo PORT` link doesn't load for others

A first-time Funnel name can take up to ~10 minutes to appear in public DNS. Test from
a phone with Wi-Fi and Tailscale off.

### Dashboard says it can't reach the API

`systemctl --user status dashboard-api`; it needs `python3-psutil` and a logged-in
Tailscale (it reads the owner and hostname from `tailscale status` at start).

### Everything stopped answering

Check the laptop is awake: on battery, closing the lid suspends it. Plugged in, it stays
reachable. `remote-on` restores all services and addresses.
