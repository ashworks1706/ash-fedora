#!/usr/bin/env python3
"""API for the remote dashboard: service control, live metrics, image paste.

Listens on 127.0.0.1 only. `tailscale serve` exposes it at /api on the dashboard and on
the web terminal, and adds a Tailscale-User-Login header; only this machine's Tailscale
owner is answered, and changes are only accepted from those two pages. Only whitelisted
start/stop actions on a fixed set of services exist.
"""
import collections
import glob
import json
import os
import platform
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psutil

BIND = ("127.0.0.1", 8095)
PASTE_DIR = os.path.expanduser("~/.cache/web-paste")
IMAGE_TYPES = {"image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp"}
MAX_IMAGE = 25 * 1024 * 1024
SAMPLE_EVERY = 2          # seconds
HISTORY = 300             # samples kept: 10 minutes
NVIDIA_PCI = "/sys/bus/pci/devices/0000:01:00.0"


def run(*cmd, env=None, timeout=20):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


# ---------------------------------------------------------------- Tailscale identity

def tailscale_status():
    try:
        return json.loads(run("tailscale", "status", "--json", timeout=5).stdout or "{}")
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        return {}


_ts = tailscale_status()
HOST = os.environ.get("DASHBOARD_HOST") or (_ts.get("Self", {}).get("DNSName") or "").rstrip(".")
OWNER = os.environ.get("DASHBOARD_OWNER") or \
    _ts.get("User", {}).get(str(_ts.get("Self", {}).get("UserID")), {}).get("LoginName", "")
ORIGIN = f"https://{HOST}"
ORIGINS = {ORIGIN, ORIGIN + ":8445"}  # dashboard and web terminal


# ---------------------------------------------------------------- services

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
    return ":8443" in run("tailscale", "funnel", "status").stdout


def demo_action(action):
    if action != "stop":
        return False  # starting a public demo needs a port: `demo PORT` on the laptop
    return run("tailscale", "funnel", "--https=8443", "off").returncode == 0


def unit(name):
    return {"status": lambda: unit_active(name), "act": lambda a: unit_action(name, a)}


SERVICES = {
    "vscode":   {**unit("code-server.service"), "name": "VS Code", "port": 8444, "local": 8080,
                 "desc": "code-server: projects, terminal and GPU in the browser"},
    "desktop":  {**unit("moonlight-web.service"), "name": "Desktop", "port": 10000, "local": 8090,
                 "desc": "Full Hyprland desktop in the browser (Moonlight Web)"},
    "terminal": {**unit("web-terminal.service"), "name": "Terminal", "port": 8445, "local": 7681,
                 "desc": "Shell in the browser, attached to your tmux sessions"},
    "sunshine": {"status": sunshine_active, "act": sunshine_action, "name": "Sunshine",
                 "port": None, "local": 47989,
                 "desc": "Streams the screen to Moonlight apps and Desktop (AMD VAAPI)"},
    "demo":     {"status": demo_active, "act": demo_action, "name": "Public demo",
                 "port": 8443, "local": None, "public": True,
                 "desc": "Public HTTPS link while demo PORT runs on the laptop"},
}


def services_view():
    return [{"id": k, "name": v["name"], "desc": v["desc"], "port": v["port"], "local": v["local"],
             "public": v.get("public", False), "active": v["status"]()} for k, v in SERVICES.items()]


# ---------------------------------------------------------------- metrics sampler

def amd_gpu_dir():
    for card in glob.glob("/sys/class/drm/card*/device"):
        if read(f"{card}/vendor") == "0x1002" and os.path.exists(f"{card}/gpu_busy_percent"):
            return card
    return None


AMD = amd_gpu_dir()
_lock = threading.Lock()
_history = collections.deque(maxlen=HISTORY)
_latest = {}
_procs = []
_last_view = 0.0          # when a client last asked for metrics
_nvidia = {"state": "unknown"}


def sample_nvidia():
    """Only query the dGPU when it's already awake and someone is watching:
    nvidia-smi wakes a runtime-suspended GPU and keeps it awake (battery)."""
    state = read(f"{NVIDIA_PCI}/power/runtime_status", "unknown")
    if state != "active":
        return {"state": state}
    if time.time() - _last_view > 30:
        return {**_nvidia, "state": "active"}
    try:
        out = run("nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,"
                  "temperature.gpu,power.draw", "--format=csv,noheader,nounits", timeout=3).stdout
        name, util, used, total, temp, power = [x.strip() for x in out.split(",")]
        return {"state": "active", "name": name, "util": float(util), "mem_used": float(used),
                "mem_total": float(total), "temp": float(temp),
                "power": float(power) if power.replace(".", "").isdigit() else None}
    except (ValueError, subprocess.TimeoutExpired):
        return {"state": "active"}


def sensors():
    temps = {}
    for name, entries in psutil.sensors_temperatures().items():
        if entries:
            temps[name] = round(entries[0].current, 1)
    fans = [int(read(f)) for f in sorted(glob.glob("/sys/class/hwmon/hwmon*/fan*_input"))
            if read(f).isdigit()]
    bat = psutil.sensors_battery()
    ac = [read(f) == "1" for f in glob.glob("/sys/class/power_supply/*/online")
          if read(os.path.join(os.path.dirname(f), "type")) == "Mains"]
    plugged = any(ac) if ac else bat.power_plugged if bat else None
    return temps, fans, ({"percent": round(bat.percent), "plugged": plugged,
                          "secs_left": bat.secsleft if bat.secsleft > 0 else None} if bat else None)


def sampler():
    global _latest, _procs, _nvidia
    psutil.cpu_percent(percpu=True)
    prev_net = psutil.net_io_counters(pernic=True)
    prev_disk = psutil.disk_io_counters()
    prev_t = time.time()
    procs = {}
    while True:
        time.sleep(SAMPLE_EVERY)
        now = time.time()
        dt = now - prev_t
        prev_t = now

        cores = psutil.cpu_percent(percpu=True)
        vm, sw = psutil.virtual_memory(), psutil.swap_memory()
        net = psutil.net_io_counters(pernic=True)
        rx = sum(n.bytes_recv - prev_net[k].bytes_recv for k, n in net.items() if k != "lo" and k in prev_net)
        tx = sum(n.bytes_sent - prev_net[k].bytes_sent for k, n in net.items() if k != "lo" and k in prev_net)
        prev_net = net
        disk = psutil.disk_io_counters()
        rd = (disk.read_bytes - prev_disk.read_bytes) / dt
        wr = (disk.write_bytes - prev_disk.write_bytes) / dt
        prev_disk = disk
        temps, fans, battery = sensors()
        igpu = None
        if AMD:
            igpu = {"util": int(read(f"{AMD}/gpu_busy_percent", "0") or 0),
                    "mem_used": int(read(f"{AMD}/mem_info_vram_used", "0")) / 2**20,
                    "mem_total": int(read(f"{AMD}/mem_info_vram_total", "0")) / 2**20}
        _nvidia = sample_nvidia()

        # Process table (htop-like): CPU% needs two readings per process.
        current = {}
        for p in psutil.process_iter(["pid", "name", "username", "memory_info"]):
            proc = procs.get(p.pid, p)
            try:
                cpu = proc.cpu_percent(None)
                current[p.pid] = proc
                rss = p.info["memory_info"].rss if p.info["memory_info"] else 0
                current_row = (cpu, p.pid, p.info["name"], p.info["username"], rss)
                proc._row = current_row
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        procs = current
        rows = sorted((p._row for p in procs.values() if hasattr(p, "_row")), reverse=True)[:12]

        point = {
            "t": round(now), "cpu": round(sum(cores) / len(cores), 1), "mem": vm.percent,
            "swap": sw.percent, "rx": round(rx / dt), "tx": round(tx / dt),
            "disk_r": round(rd), "disk_w": round(wr),
            "igpu": igpu["util"] if igpu else None, "dgpu": _nvidia.get("util"),
            "temp_cpu": temps.get("k10temp"), "temp_gpu": temps.get("amdgpu"),
        }
        with _lock:
            _history.append(point)
            _latest = {
                **point, "cores": cores, "load": os.getloadavg(),
                "mem_used": vm.used, "mem_total": vm.total, "swap_used": sw.used, "swap_total": sw.total,
                "disk": psutil.disk_usage("/")._asdict(), "temps": temps, "fans": fans,
                "battery": battery, "igpu_detail": igpu, "nvidia": _nvidia,
            }
            _procs = [{"cpu": round(c, 1), "pid": pid, "name": n, "user": u, "rss": r}
                      for c, pid, n, u, r in rows]


# ---------------------------------------------------------------- info

def cpu_model():
    for line in read("/proc/cpuinfo").splitlines():
        if line.startswith("model name"):
            return line.split(":", 1)[1].strip()
    return platform.processor()


def os_name():
    for line in read("/etc/os-release").splitlines():
        if line.startswith("PRETTY_NAME="):
            return line.split("=", 1)[1].strip('"')
    return platform.system()


def tmux_sessions():
    out = run("tmux", "list-sessions", "-F",
              "#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_activity}").stdout
    rows = []
    for line in out.splitlines():
        name, windows, attached, activity = line.split("\t")
        rows.append({"name": name, "windows": int(windows), "attached": int(attached),
                     "activity": int(activity)})
    return rows


def info():
    ts = tailscale_status()
    me = ts.get("Self", {})
    peers = [{"name": (p.get("DNSName") or p.get("HostName", "")).split(".")[0], "os": p.get("OS"),
              "online": p.get("Online", False), "ip": (p.get("TailscaleIPs") or [""])[0],
              "last_seen": p.get("LastSeen")}
             for p in ts.get("Peer", {}).values()]
    return {
        "hostname": socket.gethostname(), "user": os.environ.get("USER", ""),
        "os": os_name(), "kernel": platform.release(), "cpu": cpu_model(),
        "cores": psutil.cpu_count(), "mem_total": psutil.virtual_memory().total,
        "boot_time": psutil.boot_time(),
        "gpus": {"amd": bool(AMD), "nvidia": os.path.exists(NVIDIA_PCI)},
        "tailscale": {"host": HOST, "ip": (me.get("TailscaleIPs") or [""])[0], "user": OWNER,
                      "peers": sorted(peers, key=lambda p: (not p["online"], p["name"]))},
        "tmux": tmux_sessions(),
        "services": services_view(),
    }


# ---------------------------------------------------------------- HTTP

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
        return bool(OWNER) and self.headers.get("Tailscale-User-Login") == OWNER

    def _route(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        return path[4:] if path.startswith("/api") else path

    def do_GET(self):
        global _last_view
        if not self._authorized():
            return self._send(403, {"error": "forbidden"})
        route = self._route()
        if route in ("", "/status"):
            return self._send(200, {k: v["status"]() for k, v in SERVICES.items()})
        if route == "/info":
            return self._send(200, info())
        if route == "/metrics":
            _last_view = time.time()
            with _lock:
                return self._send(200, {"now": _latest, "history": list(_history), "procs": _procs})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        # Only the dashboard and web terminal pages may change things.
        if not self._authorized() or self.headers.get("Origin") not in ORIGINS \
                or self.headers.get("X-Dashboard") != "1":
            return self._send(403, {"error": "forbidden"})
        route = self._route()
        if route == "/paste-image":
            return self._paste_image()
        parts = [p for p in route.split("/") if p]
        if len(parts) != 2 or parts[0] not in SERVICES or parts[1] not in ("start", "stop"):
            return self._send(404, {"error": "not found"})
        name, action = parts
        ok = SERVICES[name]["act"](action)
        self._send(200 if ok else 500, {"ok": ok, name: SERVICES[name]["status"]()})

    def _paste_image(self):
        """Save an image pasted into the web terminal; reply with its path so the
        page can type it (Claude Code and most CLIs accept image file paths)."""
        ext = IMAGE_TYPES.get(self.headers.get("Content-Type", "").split(";")[0].strip())
        size = int(self.headers.get("Content-Length") or 0)
        if not ext or not 0 < size <= MAX_IMAGE:
            return self._send(400, {"error": "unsupported image"})
        os.makedirs(PASTE_DIR, mode=0o700, exist_ok=True)
        for old in glob.glob(os.path.join(PASTE_DIR, "paste-*")):  # keep a week
            if time.time() - os.path.getmtime(old) > 7 * 86400:
                os.remove(old)
        path = os.path.join(PASTE_DIR, f"paste-{time.strftime('%Y%m%d-%H%M%S')}-{os.urandom(2).hex()}.{ext}")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(self.rfile.read(size))
        self._send(200, {"path": path})

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=sampler, daemon=True).start()
    ThreadingHTTPServer(BIND, Handler).serve_forever()
