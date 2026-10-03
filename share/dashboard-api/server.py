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
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psutil

BIND = ("127.0.0.1", 8095)
PASTE_DIR = os.path.expanduser("~/.cache/web-paste")
IMAGE_TYPES = {"image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp"}
MAX_IMAGE = 25 * 1024 * 1024
SAMPLE_EVERY = 2          # seconds, while the dashboard is open
IDLE_EVERY = 30           # seconds, when nobody has looked for WATCH_WINDOW
WATCH_WINDOW = 60
HISTORY_SECONDS = 600     # graphs show the last 10 minutes
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
    # `demo` runs Funnel in the foreground; those sessions only appear under "Foreground"
    # in the JSON status, not in the plain-text `tailscale funnel status`.
    try:
        st = json.loads(run("tailscale", "serve", "status", "--json").stdout or "{}")
    except ValueError:
        return False
    return ":8443" in json.dumps(st.get("Foreground", {})) + json.dumps(st.get("AllowFunnel", {}))


def demo_action(action):
    if action != "stop":
        return False  # starting a public demo needs a port: `demo PORT` on the laptop
    run("pkill", "-f", "^tailscale funnel --https=8443 ")  # only the session `demo` runs (anchored)
    run("tailscale", "funnel", "--https=8443", "off")
    time.sleep(1)
    return not demo_active()


def unit(name):
    return {"status": lambda: unit_active(name), "act": lambda a: unit_action(name, a)}


SERVICES = {
    "vscode":   {**unit("code-server.service"), "name": "VS Code", "port": 8444, "local": 8080,
                 "desc": "code-server: projects, terminal and GPU in the browser"},
    "desktop":  {**unit("moonlight-web.service"), "name": "Desktop", "port": 10000, "local": 8090,
                 "desc": "Full Hyprland desktop in the browser (Moonlight Web)"},
    "terminal": {**unit("web-terminal.service"), "name": "Terminal", "port": 8445, "local": 7681,
                 "desc": "Shell in the browser, attached to your tmux sessions"},
    "models":   {**unit("llama-swap.service"), "name": "Model server", "port": 8100, "local": 8100,
                 "desc": "llama-swap: one OpenAI-compatible endpoint for every local model"},
    "hermes":   {**unit("hermes-gateway.service"), "name": "Hermes", "port": None, "local": None,
                 "desc": "Hermes agent (Discord bot); local fallback runs on the model server"},
    "ntfy":     {**unit("ntfy.service"), "name": "Notifications", "port": 8447, "local": 2586,
                 "desc": "ntfy: pushes alerts and notify messages to your phone and browsers"},
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
_history = collections.deque()
_wake = threading.Event()  # set by /metrics so an idle sampler speeds up immediately
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
    fans = []
    for f in sorted(glob.glob("/sys/class/hwmon/hwmon*/fan*_input")):
        if read(f).isdigit():
            label = read(f.replace("_input", "_label")) or os.path.basename(f).replace("_input", "")
            fans.append({"name": label.replace("_fan", "").upper(), "rpm": int(read(f))})
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
        watched = time.time() - _last_view < WATCH_WINDOW
        _wake.wait(SAMPLE_EVERY if watched else IDLE_EVERY)
        _wake.clear()
        now = time.time()
        watched = now - _last_view < WATCH_WINDOW
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
        gen_tps, pp_tps = ai_rates() if watched else (None, None)

        # Process table (htop-like), only while someone is looking: scanning every
        # process is the sampler's main cost. CPU% needs two readings per process.
        current = {}
        for p in (psutil.process_iter(["pid", "name", "username", "memory_info"]) if watched else ()):
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
            "gen_tps": gen_tps, "pp_tps": pp_tps,
            "fan_cpu": next((f["rpm"] for f in fans if f["name"] == "CPU"), None),
            "fan_gpu": next((f["rpm"] for f in fans if f["name"] == "GPU"), None),
        }
        with _lock:
            _history.append(point)
            while _history and _history[0]["t"] < now - HISTORY_SECONDS:
                _history.popleft()
            _latest = {
                **point, "cores": cores, "load": os.getloadavg(),
                "mem_used": vm.used, "mem_total": vm.total, "swap_used": sw.used, "swap_total": sw.total,
                "disk": psutil.disk_usage("/")._asdict(), "temps": temps, "fans": fans,
                "battery": battery, "igpu_detail": igpu, "nvidia": _nvidia,
                # ACPI platform profile (set by asusctl / power-profiles): drives the fan curve
                "power_profile": read("/sys/firmware/acpi/platform_profile") or None,
            }
            if watched:
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


# ---------------------------------------------------------------- AI (llama-swap)

LLM_URL = os.environ.get("LLM_URL", "http://127.0.0.1:8100")      # llama-swap


def env_value(path, key):
    """Read KEY=value from an env file (keys stay server-side, never sent to the browser)."""
    for line in read(os.path.expanduser(path)).splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return ""


def llm_key():
    return env_value("~/.config/llm/env", "LLM_API_KEY")


def upstream(url, key, data=None, timeout=10):
    req = urllib.request.Request(url, data=data, method="POST" if data is not None else "GET")
    req.add_header("Authorization", f"Bearer {key}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    return urllib.request.urlopen(req, timeout=timeout)


def ai_models():
    """Local models from llama-swap, and which are loaded."""
    out = {"models": [], "running": [], "llm": False}
    try:
        with upstream(f"{LLM_URL}/v1/models", llm_key()) as r:
            out["models"] = [{"id": m["id"], "name": m.get("name") or m["id"],
                              "description": m.get("description", ""), "kind": "local"}
                             for m in json.load(r).get("data", [])]
        out["llm"] = True
        with upstream(f"{LLM_URL}/running", llm_key()) as r:
            out["running"] = [m.get("model") for m in json.load(r).get("running", [])
                              if m.get("state") in ("ready", "starting")]
    except (urllib.error.URLError, OSError, ValueError, KeyError):
        pass
    return out


def llm_json(path, timeout=5):
    with upstream(f"{LLM_URL}{path}", llm_key(), timeout=timeout) as r:
        return json.load(r)


# llama-server Prometheus counters (enabled with --metrics) -> short names
METRICS = {
    "llamacpp:prompt_tokens_total": "prompt_tokens",
    "llamacpp:prompt_seconds_total": "prompt_seconds",
    "llamacpp:tokens_predicted_total": "gen_tokens",
    "llamacpp:tokens_predicted_seconds_total": "gen_seconds",
    "llamacpp:n_decode_total": "decodes",
    "llamacpp:requests_processing": "processing",
    "llamacpp:requests_deferred": "deferred",
}


def model_metrics(model_id):
    out = {}
    with upstream(f"{LLM_URL}/upstream/{model_id}/metrics", llm_key(), timeout=3) as r:
        for line in r.read().decode().splitlines():
            if line and not line.startswith("#"):
                name, _, value = line.partition(" ")
                if name in METRICS:
                    out[METRICS[name]] = float(value)
    return out


def running_models():
    try:
        return [m for m in llm_json("/running", 3).get("running", []) if m.get("state") == "ready"]
    except (urllib.error.URLError, OSError, ValueError):
        return []


_ai_prev = {}  # model -> (time, gen_tokens, prompt_tokens) for live rates


def ai_rates():
    """Tokens per second across loaded models since the last call (sampler, while watched)."""
    now, gen, pp = time.time(), 0.0, 0.0
    for m in running_models():
        mid = m["model"]
        try:
            c = model_metrics(mid)
            slots = llm_json(f"/upstream/{mid}/slots", 3)
        except (urllib.error.URLError, OSError, ValueError):
            continue
        # Counters only grow when a request finishes; add in-progress tokens from the
        # slots so long replies show up live. A finished request moves from one to the
        # other, so the total stays continuous.
        busy = [x for x in slots if x.get("is_processing")]
        gen_total = c.get("gen_tokens", 0) + sum((x.get("next_token") or [{}])[0].get("n_decoded", 0) for x in busy)
        pp_total = c.get("prompt_tokens", 0) + sum(x.get("n_prompt_tokens_processed", 0) for x in busy)
        prev = _ai_prev.get(mid)
        _ai_prev[mid] = (now, gen_total, pp_total)
        if prev and now > prev[0]:
            gen += max(0, gen_total - prev[1]) / (now - prev[0])
            pp += max(0, pp_total - prev[2]) / (now - prev[0])
    return round(gen, 1), round(pp, 1)


def ai_status():
    """Models, which are loaded, and per-loaded-model details and inference stats."""
    out = ai_models()
    details = []
    for m in running_models():
        mid = m["model"]
        d = {"id": mid, "slots": [], "ctx_per_slot": None, "busy": 0}
        try:
            slots = llm_json(f"/upstream/{mid}/slots", 3)
            d["slots"] = [{"id": x.get("id"), "processing": x.get("is_processing", False)} for x in slots]
            d["ctx_per_slot"] = slots[0].get("n_ctx") if slots else None
            d["busy"] = sum(1 for x in slots if x.get("is_processing"))
        except (urllib.error.URLError, OSError, ValueError, IndexError):
            pass
        try:
            props = llm_json(f"/upstream/{mid}/props", 3)
            d["file"] = os.path.basename(props.get("model_path", ""))
            d["modalities"] = [k for k, v in (props.get("modalities") or {}).items() if v]
            d["build"] = props.get("build_info", "")
        except (urllib.error.URLError, OSError, ValueError):
            pass
        try:
            c = model_metrics(mid)
            d["stats"] = {
                "gen_tokens": int(c.get("gen_tokens", 0)),
                "prompt_tokens": int(c.get("prompt_tokens", 0)),
                "gen_tps": round(c["gen_tokens"] / c["gen_seconds"], 1) if c.get("gen_seconds") else None,
                "prompt_tps": round(c["prompt_tokens"] / c["prompt_seconds"], 1) if c.get("prompt_seconds") else None,
                "processing": int(c.get("processing", 0)),
                "deferred": int(c.get("deferred", 0)),
            }
        except (urllib.error.URLError, OSError, ValueError):
            pass
        cmd = m.get("cmd", "")
        d["gpu"] = "-ngl 0" not in cmd
        details.append(d)
    out["loaded"] = details
    return out


def ai_load(model_id):
    """Start a model by touching its upstream (llama-swap loads on first request)."""
    if model_id not in {m["id"] for m in ai_models()["models"]}:
        return False
    with upstream(f"{LLM_URL}/upstream/{model_id}/health", llm_key(), timeout=240):
        return True


# ---------------------------------------------------------------- notifications (ntfy)

NOTIFY_SETTINGS = os.path.expanduser("~/.config/dashboard/notify.json")
NOTIFY_EVENTS = [  # key, default, label, description
    ("unplugged", True, "Unplugged", "On battery: closing the lid will suspend and remote access drops"),
    ("plugged", False, "Plugged in", "Back on AC power"),
    ("battery_low", True, "Battery low", "Battery at 20%, and again at 10%"),
    ("service_failed", True, "Service crashed", "A service failed or crashed (stopping one yourself never alerts)"),
    ("boot", True, "Back online", "The laptop rebooted and services are back"),
    ("disk", True, "Disk almost full", "Root disk above 90%"),
    ("hot", True, "Running hot", "CPU at 95°C or GPU at 90°C for 3 minutes"),
    ("demo", True, "Public demo", "A public demo link went live, and a reminder after an hour"),
    ("ssh", True, "SSH login", "Someone signed in over Tailscale SSH"),
    ("taildrop", True, "File received", "A file arrived via Taildrop"),
    ("model", False, "AI model", "A model loaded on the GPU or unloaded"),
]
WATCHED_UNITS = ["tmux", "web-terminal", "code-server", "moonlight-web", "llama-swap",
                 "hermes-gateway", "taildrop-receive", "ntfy"]
_recent = collections.deque(maxlen=25)


def notify_settings():
    try:
        with open(NOTIFY_SETTINGS) as f:
            saved = json.load(f)
    except (OSError, ValueError):
        saved = {}
    events = {k: saved.get("events", {}).get(k, default) for k, default, *_ in NOTIFY_EVENTS}
    return {"enabled": saved.get("enabled", True), "events": events}


def save_notify_settings(settings):
    os.makedirs(os.path.dirname(NOTIFY_SETTINGS), exist_ok=True)
    with open(NOTIFY_SETTINGS, "w") as f:
        json.dump(settings, f, indent=2)


def ntfy_client():
    return {k: env_value("~/.config/ntfy/client.env", k) for k in ("NTFY_URL", "NTFY_TOPIC", "NTFY_TOKEN")}


def send_notification(title, message, priority="default", tags="", click="", event=None):
    """Publish to ntfy. Returns True on success; failures are kept in the recent list."""
    if event is not None:
        st = notify_settings()
        if not st["enabled"] or not st["events"].get(event, False):
            return False
    c = ntfy_client()
    req = urllib.request.Request(f"{c['NTFY_URL'] or 'http://127.0.0.1:2586'}/{c['NTFY_TOPIC'] or 'ash-fedora'}",
                                 data=message.encode(), method="POST")
    req.add_header("Title", title)
    req.add_header("Priority", priority)
    if tags:
        req.add_header("Tags", tags)
    if click:
        req.add_header("Click", click)
    if c["NTFY_TOKEN"]:
        req.add_header("Authorization", f"Bearer {c['NTFY_TOKEN']}")
    try:
        with urllib.request.urlopen(req, timeout=10):
            ok = True
    except (urllib.error.URLError, OSError):
        ok = False
    _recent.appendleft({"t": int(time.time()), "title": title, "message": message,
                        "event": event or "manual", "ok": ok})
    return ok


def unit_props(unit):
    out = run("systemctl", "--user", "show", f"{unit}.service",
              "-p", "ActiveState", "-p", "Result", "-p", "NRestarts").stdout
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def journal_since(since, *args):
    return run("journalctl", "--no-pager", "-q", "-o", "cat", "--since", f"@{int(since)}", *args).stdout


def notifier():
    """Watch for events every 15 s and publish the enabled ones."""
    dash = f"https://{HOST}"
    last = time.time()
    state = {"plugged": None, "bat_alert": 100, "disk_alert": False, "hot_since": None,
             "hot_alert": False, "demo_since": None, "demo_reminded": False, "models": None,
             "units": {u: unit_props(u) for u in WATCHED_UNITS}}
    if time.time() - psutil.boot_time() < 900:
        time.sleep(60)  # let services finish starting
        down = [u for u in WATCHED_UNITS if unit_active(f"{u}.service") is False
                and run("systemctl", "--user", "is-enabled", f"{u}.service").stdout.strip() == "enabled"]
        send_notification("Back online", "Rebooted; " + (f"not running: {', '.join(down)}" if down
                          else "all services are up"), tags="arrows_counterclockwise", click=dash, event="boot")
    while True:
        time.sleep(15)
        now = time.time()
        quiet = os.path.exists(os.path.expanduser("~/.config/remote-off"))

        # power
        _, _, bat = sensors()
        if bat:
            plugged, pct = bat["plugged"], bat["percent"]
            if state["plugged"] is True and plugged is False:
                send_notification("Unplugged", f"On battery at {pct}%. Closing the lid will suspend the "
                                  "laptop and remote access will drop.", "high", "electric_plug", dash, "unplugged")
            if state["plugged"] is False and plugged is True:
                send_notification("Plugged in", f"Charging at {pct}%.", "low", "zap", dash, "plugged")
                state["bat_alert"] = 100
            if not plugged:
                for level in (20, 10):
                    if pct <= level < state["bat_alert"]:
                        send_notification("Battery low", f"{pct}% and on battery.", "urgent" if level == 10 else "high",
                                          "battery", dash, "battery_low")
                        state["bat_alert"] = level
            state["plugged"] = plugged

        # crashed / failed services (clean stops have Result=success and never alert)
        for u in WATCHED_UNITS:
            cur, prev = unit_props(u), state["units"].get(u, {})
            crashed = cur.get("NRestarts", "0") != prev.get("NRestarts", "0")
            failed = cur.get("ActiveState") == "failed" and prev.get("ActiveState") != "failed"
            if (crashed or failed) and not quiet:
                restarted = crashed and cur.get("ActiveState") == "active"
                what = "crashed and was restarted" if restarted else "failed"
                detail = "" if restarted else f" (result: {cur.get('Result', '?')})"
                send_notification(f"{u} {what}", f"{u}.service {what}{detail}. "
                                  f"Logs: journalctl --user -u {u}", "high", "warning", dash, "service_failed")
            state["units"][u] = cur

        # disk (hysteresis: re-arm below 85%)
        pct = psutil.disk_usage("/").percent
        if pct >= 90 and not state["disk_alert"]:
            send_notification("Disk almost full", f"Root disk is {pct:.0f}% full.", "high", "floppy_disk", dash, "disk")
            state["disk_alert"] = True
        elif pct < 85:
            state["disk_alert"] = False

        # heat: sustained 3 minutes (re-arm after cooling down)
        temps, _, _ = sensors()
        hot = (temps.get("k10temp") or 0) >= 95 or (_nvidia.get("temp") or 0) >= 90
        if hot:
            state["hot_since"] = state["hot_since"] or now
            if now - state["hot_since"] >= 180 and not state["hot_alert"]:
                send_notification("Running hot", f"CPU {temps.get('k10temp')}°C, GPU {_nvidia.get('temp', '–')}°C "
                                  "for 3 minutes.", "high", "fire", dash, "hot")
                state["hot_alert"] = True
        else:
            state["hot_since"], state["hot_alert"] = None, False

        # public demo
        live = demo_active()
        if live and state["demo_since"] is None:
            state["demo_since"], state["demo_reminded"] = now, False
            send_notification("Public demo is live", f"https://{HOST}:8443 is open to anyone with the link. "
                              "Stop it with Ctrl+C or from the dashboard.", "default", "globe_with_meridians",
                              dash, "demo")
        elif live and now - state["demo_since"] > 3600 and not state["demo_reminded"]:
            state["demo_reminded"] = True
            send_notification("Demo still public", "The public demo link has been live for over an hour.",
                              "high", "globe_with_meridians", dash, "demo")
        elif not live:
            state["demo_since"] = None

        # SSH logins (Tailscale SSH audit lines) and Taildrop arrivals
        for line in journal_since(last, "-u", "tailscaled").splitlines():
            if "SSH login: user=" in line:
                who = dict(kv.split("=", 1) for kv in line.split() if "=" in kv)
                send_notification("SSH login", f"{who.get('ts_user', '?')} as {who.get('user', '?')} from "
                                  f"{who.get('node', who.get('from', '?')).split('.')[0]}", "default", "key",
                                  event="ssh")
        for line in journal_since(last, "--user", "-u", "taildrop-receive", "-t", "tailscale").splitlines():
            # verbose `tailscale file get` also prints status lines such as "waiting for file..."
            if line.strip() and "waiting" not in line.lower() and \
                    any(w in line.lower() for w in ("wrote", "moved", "saved", "received", "downloads")):
                send_notification("File received", line.strip()[:300], "default", "inbox_tray", event="taildrop")

        # AI model loaded/unloaded
        loaded = {m["model"] for m in running_models() if "-ngl 0" not in m.get("cmd", "")}
        if state["models"] is not None and loaded != state["models"] and not quiet:
            added, removed = loaded - state["models"], state["models"] - loaded
            send_notification("AI model " + ("loaded" if added else "unloaded"),
                              ", ".join(sorted(added or removed)), "low", "robot", dash, "model")
        state["models"] = loaded
        last = now


def ntfy_history(limit=8):
    """Recent messages from ntfy's own cache (survives restarts; includes `notify` CLI messages)."""
    c = ntfy_client()
    url = f"{c['NTFY_URL'] or 'http://127.0.0.1:2586'}/{c['NTFY_TOPIC'] or 'ash-fedora'}/json?poll=1&since=72h"
    req = urllib.request.Request(url)
    if c["NTFY_TOKEN"]:
        req.add_header("Authorization", f"Bearer {c['NTFY_TOKEN']}")
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            msgs = [json.loads(line) for line in r.read().decode().splitlines() if line.strip()]
    except (urllib.error.URLError, OSError, ValueError):
        return None
    msgs = [m for m in msgs if m.get("event") == "message"][-limit:]
    return [{"t": m.get("time"), "title": m.get("title", ""), "message": m.get("message", ""),
             "event": "ntfy", "ok": True} for m in reversed(msgs)]


def notify_view():
    st = notify_settings()
    c = ntfy_client()
    history = ntfy_history()
    failed = [r for r in _recent if not r["ok"]]  # sends that never reached ntfy
    return {"enabled": st["enabled"],
            "events": [{"key": k, "label": label, "desc": desc, "on": st["events"][k]}
                       for k, _, label, desc in NOTIFY_EVENTS],
            "recent": (failed + history) if history is not None else list(_recent),
            "server": f"https://{HOST}:8447", "topic": c["NTFY_TOPIC"] or "ash-fedora",
            "configured": bool(c["NTFY_TOKEN"])}


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
        if route == "/ai/models":
            return self._send(200, ai_models())
        if route == "/notify":
            return self._send(200, notify_view())
        if route == "/ai/status":
            return self._send(200, ai_status())
        if route == "/metrics":
            if time.time() - _last_view >= WATCH_WINDOW:
                _wake.set()  # was idle: sample at full speed from now on
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
        if route == "/notify/test":
            ok = send_notification("Test from the dashboard", "If you can read this, notifications work.",
                                   tags="tada", click=ORIGIN)
            return self._send(200 if ok else 502, {"ok": ok})
        if route == "/notify/settings":
            try:
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
            except ValueError:
                return self._send(400, {"error": "invalid JSON"})
            st = notify_settings()
            if isinstance(body.get("enabled"), bool):
                st["enabled"] = body["enabled"]
            for k, v in (body.get("events") or {}).items():
                if k in st["events"] and isinstance(v, bool):
                    st["events"][k] = v
            save_notify_settings(st)
            return self._send(200, notify_view())
        if route.startswith("/ai/load/"):
            try:
                return self._send(200 if ai_load(route[len("/ai/load/"):]) else 404, {"ok": True})
            except (urllib.error.URLError, OSError) as e:
                return self._send(502, {"error": str(e)})
        if route == "/ai/unload":
            try:
                with upstream(f"{LLM_URL}/unload", llm_key()):
                    return self._send(200, {"ok": True})
            except (urllib.error.URLError, OSError) as e:
                return self._send(502, {"error": str(e)})
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
    threading.Thread(target=notifier, daemon=True).start()
    ThreadingHTTPServer(BIND, Handler).serve_forever()
