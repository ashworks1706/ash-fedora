#!/usr/bin/env python3
"""Emit one lightweight JSON performance snapshot for the cheatsheet panel."""

from __future__ import annotations

import glob
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import time
from pathlib import Path
from typing import Any


def read(path: str, default: str = "") -> str:
    try:
        return Path(path).read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return default


def number(path: str, divisor: float = 1.0) -> float:
    try:
        return float(read(path, "0")) / divisor
    except ValueError:
        return 0.0


def run(command: list[str], timeout: float = 1.5) -> str:
    try:
        return subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            check=False,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def cpu_ticks() -> list[list[int]]:
    rows: list[list[int]] = []
    for line in read("/proc/stat").splitlines():
        if not re.match(r"^cpu(?:\d+)?\s", line):
            continue
        rows.append([int(value) for value in line.split()[1:]])
    return rows


def interface_bytes(interface: str) -> tuple[int, int]:
    if not interface:
        return 0, 0
    return (
        int(number(f"/sys/class/net/{interface}/statistics/rx_bytes")),
        int(number(f"/sys/class/net/{interface}/statistics/tx_bytes")),
    )


def disk_ticks(device: str) -> tuple[int, int]:
    if not device:
        return 0, 0
    for line in read("/proc/diskstats").splitlines():
        fields = line.split()
        if len(fields) >= 14 and fields[2] == device:
            return int(fields[5]), int(fields[9])
    return 0, 0


def hwmon_snapshot() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    temperatures: list[dict[str, Any]] = []
    fans: list[dict[str, Any]] = []
    for directory in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        chip = read(f"{directory}/name", Path(directory).name)
        for source in sorted(glob.glob(f"{directory}/temp*_input")):
            index = re.search(r"temp(\d+)_input", source)
            label = read(f"{directory}/temp{index.group(1)}_label") if index else ""
            value = number(source, 1000)
            if -20 < value < 150:
                temperatures.append({"name": label or chip, "chip": chip, "c": round(value, 1)})
        for source in sorted(glob.glob(f"{directory}/fan*_input")):
            index = re.search(r"fan(\d+)_input", source)
            label = read(f"{directory}/fan{index.group(1)}_label") if index else ""
            fans.append({"name": label or f"{chip} fan", "rpm": int(number(source))})
    # Keep useful readings and suppress duplicate generic ACPI sensors.
    preferred = [item for item in temperatures if item["chip"] in {"k10temp", "amdgpu", "nvme", "mt7921_phy0", "asus"}]
    return (preferred or temperatures)[:10], fans[:8]


def main() -> None:
    cpu_before = cpu_ticks()

    route = run(["ip", "route", "show", "default"])
    route_match = re.search(r"\bdev\s+(\S+)", route)
    interface = route_match.group(1) if route_match else ""
    net_before = interface_bytes(interface)

    root_source = run(["findmnt", "-no", "SOURCE", "/"])
    source_name = Path(root_source).name
    disk_device = re.sub(r"p\d+$", "", source_name) if source_name.startswith("nvme") else re.sub(r"\d+$", "", source_name)
    disk_before = disk_ticks(disk_device)

    time.sleep(0.18)

    cpu_after = cpu_ticks()
    usages: list[float] = []
    for before, after in zip(cpu_before, cpu_after):
        total = sum(after) - sum(before)
        idle = (after[3] + (after[4] if len(after) > 4 else 0)) - (before[3] + (before[4] if len(before) > 4 else 0))
        usages.append(round(max(0.0, min(100.0, 100.0 * (1.0 - idle / total))), 1) if total else 0.0)

    net_after = interface_bytes(interface)
    disk_after = disk_ticks(disk_device)
    sample_seconds = 0.18

    cpuinfo = read("/proc/cpuinfo")
    model_match = re.search(r"model name\s*:\s*(.+)", cpuinfo)
    frequencies = [number(path, 1000) for path in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")]
    max_frequencies = [number(path, 1000) for path in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq")]
    load = os.getloadavg()

    meminfo: dict[str, int] = {}
    for line in read("/proc/meminfo").splitlines():
        match = re.match(r"([^:]+):\s+(\d+)", line)
        if match:
            meminfo[match.group(1)] = int(match.group(2)) * 1024

    battery: dict[str, Any] = {"available": False}
    batteries = glob.glob("/sys/class/power_supply/BAT*")
    if batteries:
        base = batteries[0]
        full = number(f"{base}/energy_full") or number(f"{base}/charge_full")
        design = number(f"{base}/energy_full_design") or number(f"{base}/charge_full_design")
        power = number(f"{base}/power_now", 1_000_000)
        battery = {
            "available": True,
            "status": read(f"{base}/status", "Unknown"),
            "percent": number(f"{base}/capacity"),
            "energyWh": round(number(f"{base}/energy_now", 1_000_000), 1),
            "fullWh": round(full / 1_000_000, 1),
            "designWh": round(design / 1_000_000, 1),
            "health": round(100 * full / design, 1) if design else 0,
            "powerW": round(power, 1),
            "voltageV": round(number(f"{base}/voltage_now", 1_000_000), 2),
            "cycles": int(number(f"{base}/cycle_count")),
            "limit": int(number(f"{base}/charge_control_end_threshold")),
        }

    wifi_line = next((line for line in run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,RATE,SECURITY", "dev", "wifi"]).splitlines() if line.startswith("*:")), "")
    wifi_parts = wifi_line.split(":", 4)
    ip_address = run(["ip", "-4", "-o", "addr", "show", "dev", interface]).split()
    ip_value = next((value.split("/")[0] for value in ip_address if re.match(r"\d+\.\d+\.\d+\.\d+/", value)), "")
    network = {
        "interface": interface,
        "ssid": wifi_parts[1] if len(wifi_parts) > 1 else "Wired" if interface else "Disconnected",
        "signal": int(wifi_parts[2]) if len(wifi_parts) > 2 and wifi_parts[2].isdigit() else 0,
        "rate": wifi_parts[3] if len(wifi_parts) > 3 else "",
        "security": wifi_parts[4] if len(wifi_parts) > 4 else "",
        "ip": ip_value,
        "downBps": round((net_after[0] - net_before[0]) / sample_seconds),
        "upBps": round((net_after[1] - net_before[1]) / sample_seconds),
        "rxBytes": net_after[0],
        "txBytes": net_after[1],
    }

    graphics_mode = run(["supergfxctl", "-g"])
    graphics_power = run(["supergfxctl", "-S"])
    nvidia: dict[str, Any] = {"available": False}
    # Avoid waking a suspended dGPU merely to populate the panel.
    nvidia_csv = run([
        "nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,pstate",
        "--format=csv,noheader,nounits",
    ], timeout=3.0) if graphics_power.lower() == "active" else ""
    if nvidia_csv:
        values = [value.strip() for value in nvidia_csv.splitlines()[0].split(",")]
        if len(values) >= 7:
            nvidia = {
                "available": True, "name": values[0], "usage": float(values[1]),
                "memoryUsedMiB": float(values[2]), "memoryTotalMiB": float(values[3]),
                "temperature": float(values[4]), "powerW": float(values[5]), "pstate": values[6],
            }

    temperatures, fans = hwmon_snapshot()
    amd_busy = number("/sys/class/drm/card1/device/gpu_busy_percent") or number("/sys/class/drm/card0/device/gpu_busy_percent")
    amd_temp = next((item["c"] for item in temperatures if item["chip"] == "amdgpu"), 0)

    disk = shutil.disk_usage("/")
    top_rows = run(["ps", "-eo", "pid=,comm=,%cpu=,%mem=", "--sort=-%cpu"]).splitlines()[:8]
    processes = []
    for row in top_rows:
        fields = row.split(None, 3)
        if len(fields) == 4:
            processes.append({"pid": fields[0], "name": fields[1], "cpu": fields[2], "memory": fields[3]})

    asus_profile = run(["asusctl", "profile", "get"]).replace("Active profile:", "").strip()
    payload = {
        "generatedAt": int(time.time()),
        "system": {
            "hostname": socket.gethostname(), "kernel": platform.release(),
            "uptimeSeconds": int(float(read("/proc/uptime", "0").split()[0])),
            "os": read("/etc/fedora-release", platform.platform()),
        },
        "cpu": {
            "model": model_match.group(1).strip() if model_match else platform.processor(),
            "usage": usages[0] if usages else 0, "cores": os.cpu_count() or 0,
            "physicalCores": len({line for line in re.findall(r"physical id\s*:\s*(\d+).*?core id\s*:\s*(\d+)", cpuinfo, re.S)}),
            "perCore": usages[1:], "load": [round(value, 2) for value in load],
            "frequencyMHz": round(sum(frequencies) / len(frequencies)) if frequencies else 0,
            "maxFrequencyMHz": round(max(max_frequencies)) if max_frequencies else 0,
        },
        "memory": {
            "total": meminfo.get("MemTotal", 0), "available": meminfo.get("MemAvailable", 0),
            "used": meminfo.get("MemTotal", 0) - meminfo.get("MemAvailable", 0),
            "swapTotal": meminfo.get("SwapTotal", 0),
            "swapUsed": meminfo.get("SwapTotal", 0) - meminfo.get("SwapFree", 0),
        },
        "battery": battery,
        "network": network,
        "graphics": {
            "nvidia": nvidia,
            "integrated": {"name": "AMD Radeon 780M", "usage": amd_busy, "temperature": amd_temp},
            "mode": graphics_mode,
            "powerStatus": graphics_power,
        },
        "asus": {"profile": asus_profile, "profiles": run(["asusctl", "profile", "list"]).splitlines()},
        "temperatures": temperatures,
        "fans": fans,
        "disk": {
            "source": root_source, "total": disk.total, "used": disk.used, "free": disk.free,
            "readBps": round((disk_after[0] - disk_before[0]) * 512 / sample_seconds),
            "writeBps": round((disk_after[1] - disk_before[1]) * 512 / sample_seconds),
        },
        "processes": processes,
    }
    print(json.dumps(payload, separators=(",", ":")))


if __name__ == "__main__":
    main()
