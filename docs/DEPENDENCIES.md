# Dependencies

`scripts/doctor.sh` checks the core ones. `scripts/setup-remote.sh` installs everything
under **Remote access** itself.

## Desktop (`scripts/install.sh`)

| Package | For |
|---|---|
| `hyprland`, `hyprlock`, `hypridle`, `xdg-desktop-portal-hyprland` | compositor, lock, idle, portals |
| `quickshell` (`quickshell-git` COPR: errornointernet/quickshell) | the `ii` bar and widgets |
| `kitty`, `tmux`, `fish` | terminal, sessions, login shell |
| JetBrains Mono Nerd Font | kitty and the web terminal (installed by `setup-remote.sh`) |
| `jq`, `rsync`, `wl-clipboard`, `cliphist`, `brightnessctl`, `playerctl` | scripts and widgets |
| `network-manager-applet`, `pavucontrol`, `gnome-keyring` + `libsecret` | applets, audio, keyring |

Optional: `matugen` (dynamic theming), `swww` (wallpapers).

## Remote access (`scripts/setup-remote.sh`)

| Package | Source | For |
|---|---|---|
| `tailscale` | pkgs.tailscale.com | private network, SSH, Taildrop, HTTPS addresses |
| `Sunshine` | COPR lizardbyte/stable | screen streaming host for Moonlight |
| `mesa-va-drivers-freeworld`, `libva-utils` | RPM Fusion free | H.264/HEVC encoding on the AMD iGPU (Fedora's Mesa omits it) |
| `code-server` | GitHub release RPM | VS Code in the browser |
| moonlight-web-stream | GitHub release (checksum-verified) | desktop in the browser |
| `ttyd` | Fedora | terminal in the browser |
| `nodejs-npm` | Fedora | building the dashboard |
| `python3-psutil` | Fedora | dashboard metrics |
| `remmina`, `remmina-plugins-vnc` | Fedora | viewing a Mac's screen (macOS Screen Sharing) |

## On the Mac / iPhone

- **Tailscale** app, signed in to the same account
- **Moonlight** (optional, lowest-latency desktop): App Store / `brew install --cask moonlight`
- Everything else (VS Code, terminal, desktop, dashboard) needs only a browser
