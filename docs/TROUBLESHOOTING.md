# Troubleshooting

## Hyprland does not load after config changes

1. Switch to TTY.
2. Restore latest backup:
   - `cd <repo>`
   - `./scripts/uninstall.sh --restore-latest`
3. Retry:
   - `start-hyprland`

## Quickshell not reloading

- Try:
  - `pkill quickshell`
  - `quickshell &`

## GitHub widget shows missing token

- Create token file:
  - `mkdir -p ~/.config/quickshell/ii/secrets`
  - `chmod 700 ~/.config/quickshell/ii/secrets`
  - `printf '%s\n' '<token>' > ~/.config/quickshell/ii/secrets/github_token`
  - `chmod 600 ~/.config/quickshell/ii/secrets/github_token`

## Widget should not fetch in background

- In `~/.config/illogical-impulse/config.json` keep:
  - `sidebar.keepRightSidebarLoaded = false`
- Keep GitHub widget disabled by default unless needed:
  - `sidebar.github.enable = false`

## Keyring asks for password on `start-hyprland`

- Ensure your PAM stack starts the keyring daemon.
- Ensure login keyring password matches your user password.
- If needed, reset with:
  - `seahorse` -> right click `Login` keyring -> `Change Password`
