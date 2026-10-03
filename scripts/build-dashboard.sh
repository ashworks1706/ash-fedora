#!/usr/bin/env bash
# Build the Next.js dashboard (dashboard/) and deploy the static export to
# ~/.local/share/dashboard, which `tailscale serve` publishes at / on the tailnet.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../dashboard"
command -v npm >/dev/null || { echo "npm not found: sudo dnf install nodejs-npm" >&2; exit 1; }
npm ci --no-audit --no-fund
NEXT_TELEMETRY_DISABLED=1 npx next build
mkdir -p "$HOME/.local/share/dashboard"
rsync -a --delete out/ "$HOME/.local/share/dashboard/"
echo "Dashboard deployed to ~/.local/share/dashboard"
