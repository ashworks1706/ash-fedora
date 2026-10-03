# Notifications

Self-hosted [ntfy](https://ntfy.sh) pushes alerts to your phone and browsers. The server
runs on this machine and is reachable only over Tailscale, at `https://<host>.ts.net:8447`.

**Setup:** `./scripts/install.sh`, then `./scripts/setup-notify.sh`.

## Subscribe

- **iPhone:**
  1. Install the **ntfy** app.
  2. Settings → **Default server** / add server `https://<host>.ts.net:8447`.
  3. Sign in as your user, with the password from `grep NTFY_PASSWORD ~/.config/ntfy/client.env`.
  4. Subscribe to the topic (the machine's hostname).
  5. Keep Tailscale connected on the phone.
- **Mac / any browser:** open the server URL, sign in, subscribe, and allow notifications.
  They arrive even with the tab closed (Web Push).

How iPhone delivery stays private: iOS only wakes apps through Apple's push service, so
ntfy sends a content-free "poll" request via ntfy.sh. The phone then fetches the actual
message from your server over Tailscale. Message text never leaves the machine.

## Sending your own

```bash
notify "training done"                        # simple message
notify -t "Deploy" -p high "failed"           # title, priority: min|low|default|high|urgent
notify -g rocket -c https://example.com msg   # emoji tags, click-through URL
make build 2>&1 | tail -5 | notify            # message from stdin
notify run python train.py --epochs 10        # alert when it finishes (exit code kept)
```

## Automatic alerts

The dashboard API watches for these and publishes the ones switched on. Toggle them in
the dashboard's **Notifications** section (saved in `~/.config/dashboard/notify.json`):

| Alert | Default | Fires when |
|---|---|---|
| Unplugged | on | the charger is removed (lid close will now suspend; remote access drops) |
| Plugged in | off | back on AC |
| Battery low | on | 20%, and again at 10%, on battery |
| Service crashed | on | a watched service fails or crashes and is restarted; stopping one yourself never alerts |
| Back online | on | after a reboot, once services are up (or lists the ones that aren't) |
| Disk almost full | on | root disk ≥ 90% (re-arms below 85%) |
| Running hot | on | CPU ≥ 95 °C or GPU ≥ 90 °C for 3 minutes |
| Public demo | on | a `demo` link goes live, and again if it is still up after an hour |
| SSH login | on | a Tailscale SSH sign-in |
| File received | on | a Taildrop file arrives |
| AI model | off | a model loads onto or unloads from the GPU |

Nothing alerts while `remote-off` is active. Checks run every 15 s.

## Security

- `auth-default-access: deny-all`: only your account can read or publish; anonymous
  requests get 403.
- Scripts and the dashboard use a publish token (`~/.config/ntfy/client.env`, mode 600);
  the web push private key is in `~/.config/ntfy/env`. Neither is committed.
- The server listens on `127.0.0.1:2586`; `tailscale serve` provides HTTPS on the tailnet.
