#!/usr/bin/env python3
"""Control API for the ash-fedora dashboard.

Listens on 127.0.0.1 only; `tailscale serve` exposes it at /api on the tailnet dashboard.
Only whitelisted actions on a fixed set of services are possible, and only for the
owner's Tailscale identity (the Tailscale-User-Login header set by tailscale serve).
"""
import glob
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OWNER = "__TS_USER__"
ORIGIN = "https://__TS_HOST__"
BIND = ("127.0.0.1", 8095)


def run(*cmd, env=None):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20, env=env)


def unit_active(unit):
    return run("systemctl", "--user", "is-active", unit).stdout.strip() == "active"


def unit_action(unit, action):
    return run("systemctl", "--user", action, unit).returncode == 0


def sunshine_active():
    return run("pgrep", "-x", "sunshine").returncode == 0


def sunshine_action(action):
    if action == "stop":
        run("pkill", "-x", "sunshine")
        return True
    # Sunshine must run inside the Hyprland session to capture the screen.
    sockets = sorted(glob.glob(f"/run/user/{os.getuid()}/hypr/*/.socket.sock"), key=os.path.getmtime)
    if not sockets:
        return False
    env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=os.path.basename(os.path.dirname(sockets[-1])))
    return run("hyprctl", "dispatch", "exec", "sunshine", env=env).returncode == 0


def demo_active():
    out = run("tailscale", "funnel", "status").stdout
    return ":8443" in out


def demo_action(action):
    if action != "stop":
        return False  # starting a public demo needs a port; use `demo PORT` on the laptop
    return run("tailscale", "funnel", "--https=8443", "off").returncode == 0


SERVICES = {
    "vscode": {"status": lambda: unit_active("code-server.service"),
               "act": lambda a: unit_action("code-server.service", a)},
    "desktop": {"status": lambda: unit_active("moonlight-web.service"),
                "act": lambda a: unit_action("moonlight-web.service", a)},
    "sunshine": {"status": sunshine_active, "act": sunshine_action},
    "demo": {"status": demo_active, "act": demo_action},
}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self):
        return self.headers.get("Tailscale-User-Login") == OWNER

    def do_GET(self):
        if not self._authorized():
            return self._send(403, {"error": "forbidden"})
        if self.path.rstrip("/") in ("", "/status", "/api/status"):
            return self._send(200, {name: svc["status"]() for name, svc in SERVICES.items()})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        # Only the dashboard page itself may change things (blocks cross-site form posts).
        if not self._authorized() or self.headers.get("Origin") != ORIGIN \
                or self.headers.get("X-Dashboard") != "1":
            return self._send(403, {"error": "forbidden"})
        parts = [p for p in self.path.split("/") if p and p != "api"]
        if len(parts) != 2 or parts[0] not in SERVICES or parts[1] not in ("start", "stop"):
            return self._send(404, {"error": "not found"})
        name, action = parts
        ok = SERVICES[name]["act"](action)
        self._send(200 if ok else 500, {"ok": ok, name: SERVICES[name]["status"]()})

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(BIND, Handler).serve_forever()
