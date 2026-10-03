# Security

## What is exposed

Everything remote is reachable **only from devices signed in to your Tailscale account**,
with one deliberate exception:

| Exposure | Who can reach it |
|---|---|
| Dashboard, VS Code, web terminal, Moonlight Web (`https://<host>.ts.net[:port]`) | your Tailscale devices |
| Sunshine / Moonlight ports | Tailscale only; the firewall rejects them on other networks |
| SSH | Tailscale SSH, authenticated by your Tailscale identity |
| `demo PORT` (`:8443`) | **anyone with the link**, only while the command runs |

Inside the tailnet, the dashboard API and web terminal also require the owner's
Tailscale identity (the `Tailscale-User-Login` header set by `tailscale serve`), and
state-changing requests must come from the dashboard or terminal pages themselves.
The API can only start/stop a fixed list of services. code-server keeps its own
password. Everything listens on `127.0.0.1` behind `tailscale serve`.

Note: the web terminal and code-server give a full shell to whoever passes those checks,
so treat your Tailscale account like an SSH key.

## Secrets and this repo

Never committed: code-server's password (a template is committed; each install
generates one), Sunshine's credentials and pairings, Moonlight Web's user database,
Google Calendar OAuth files, GitHub tokens, SSH keys.

`scripts/sync-from-system.sh` runs `scripts/check-secrets.sh`, which fails on:

- common key formats (GitHub, Google, OpenAI/Anthropic, AWS, Slack, npm, private keys)
- `password:` values and OAuth `client_secret` / `refresh_token` fields
- known-sensitive file names (`token.json`, `credentials.json`, `*.pem`, …)
- exact strings you list in `local.secrets` (gitignored), e.g. your real passwords

Run it by hand any time: `./scripts/check-secrets.sh`.

## Reporting

If you find a credential or sensitive value in this repo, don't open a public issue
with it; report privately with the value redacted.
