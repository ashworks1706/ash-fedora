# Dashboard

A small Next.js app that becomes the home page of your machine on your Tailscale
network: services with start/stop, live system graphs, an htop-style process list,
tmux sessions, Tailscale devices, copyable commands and docs links.

It is a static export (`out/`) served by `tailscale serve` at `https://<host>.ts.net/`,
so only your own devices can open it. All data comes from the API in
[`share/dashboard-api/server.py`](../share/dashboard-api/server.py), mounted at `/api` on
the same address. Nothing machine-specific is built in: hostnames, users and devices are
read from the API at runtime.

## Build and deploy

```bash
../scripts/build-dashboard.sh     # npm ci, next build, copy out/ to ~/.local/share/dashboard
```

`scripts/install.sh` runs this automatically when `npm` is available.

## Develop

```bash
npm install
npm run dev                        # http://localhost:3100
```

The dev server has no `/api`. To work against real data, open the deployed dashboard,
or run `npm run deploy` after each change.

## API

All endpoints require the Tailscale owner identity that `tailscale serve` adds
(`Tailscale-User-Login`); POSTs also require the page's own origin and `X-Dashboard: 1`.

| Endpoint | Returns |
|---|---|
| `GET /api/info` | host, OS, kernel, CPU, uptime, GPUs, Tailscale address and devices, tmux sessions, services |
| `GET /api/metrics` | latest sample, 10 minutes of history (every 2 s), top processes |
| `GET /api/status` | `{service: running}` |
| `POST /api/<service>/start\|stop` | start/stop one of the whitelisted services |
| `GET /api/ai/status` | models, which are loaded, per-model context/slots/speed/tokens served |
| `POST /api/ai/load/<model>` \| `POST /api/ai/unload` | warm a model up / unload all models |
| `GET /api/notify` | alert switches, recent notifications (from ntfy), subscribe info |
| `POST /api/notify/settings` \| `POST /api/notify/test` | toggle alerts (`{"enabled": bool, "events": {key: bool}}`) / send a test |
| `POST /api/paste-image` | used by the web terminal: saves an image, returns its path |

The NVIDIA GPU is only queried while it is already awake and the dashboard is open:
`nvidia-smi` would otherwise wake a sleeping hybrid-laptop dGPU and drain the battery.

## Files

| Path | What |
|---|---|
| `app/page.tsx` | Page layout and polling |
| `components/sections.tsx` | Services, metrics, processes, sessions, devices, commands, docs |
| `components/Chart.tsx` | Dependency-free SVG area chart |
| `lib/api.ts` | Types, polling hook, formatters |
| `app/globals.css` | Styles (light and dark follow the system) |
