"use client";

import { useCallback, useEffect, useRef, useState } from "react";

export type Service = {
  id: string;
  name: string;
  desc: string;
  port: number | null;
  local: number | null;
  public: boolean;
  active: boolean;
};

export type Peer = { name: string; os: string; online: boolean; ip: string; last_seen?: string };
export type Session = { name: string; windows: number; attached: number; activity: number };

export type Info = {
  hostname: string;
  user: string;
  os: string;
  kernel: string;
  cpu: string;
  cores: number;
  mem_total: number;
  boot_time: number;
  gpus: { amd: boolean; nvidia: boolean };
  tailscale: { host: string; ip: string; user: string; peers: Peer[] };
  tmux: Session[];
  services: Service[];
};

export type Point = {
  t: number;
  cpu: number;
  mem: number;
  swap: number;
  rx: number;
  tx: number;
  disk_r: number;
  disk_w: number;
  igpu: number | null;
  dgpu: number | null;
  temp_cpu: number | null;
  temp_gpu: number | null;
};

export type Nvidia = {
  state: string;
  name?: string;
  util?: number;
  mem_used?: number;
  mem_total?: number;
  temp?: number;
  power?: number | null;
};

export type Now = Point & {
  cores: number[];
  load: [number, number, number];
  mem_used: number;
  mem_total: number;
  swap_used: number;
  swap_total: number;
  disk: { total: number; used: number; free: number; percent: number };
  temps: Record<string, number>;
  fans: number[];
  battery: { percent: number; plugged: boolean | null; secs_left: number | null } | null;
  igpu_detail: { util: number; mem_used: number; mem_total: number } | null;
  nvidia: Nvidia;
};

export type Proc = { cpu: number; pid: number; name: string; user: string; rss: number };
export type Metrics = { now: Now | Record<string, never>; history: Point[]; procs: Proc[] };

async function getJSON<T>(path: string): Promise<T> {
  const r = await fetch(path, { cache: "no-store" });
  if (!r.ok) throw new Error(`${path}: HTTP ${r.status}`);
  return r.json() as Promise<T>;
}

/** Poll an endpoint; `error` is set while the API can't be reached. */
export function usePoll<T>(path: string, every: number) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const refresh = useCallback(async () => {
    try {
      setData(await getJSON<T>(path));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, [path]);

  useEffect(() => {
    let alive = true;
    const loop = async () => {
      await refresh();
      if (alive) timer.current = setTimeout(loop, every);
    };
    loop();
    return () => {
      alive = false;
      if (timer.current) clearTimeout(timer.current);
    };
  }, [refresh, every]);

  return { data, error, refresh };
}

export async function serviceAction(id: string, action: "start" | "stop") {
  const r = await fetch(`/api/${id}/${action}`, { method: "POST", headers: { "X-Dashboard": "1" } });
  return r.ok;
}

export const fmt = {
  bytes(n: number, digits = 1) {
    if (!Number.isFinite(n)) return "–";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let i = 0;
    while (Math.abs(n) >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return `${n.toFixed(i === 0 ? 0 : digits)} ${units[i]}`;
  },
  rate(n: number) {
    return `${fmt.bytes(n)}/s`;
  },
  pct(n: number | null | undefined) {
    return n == null ? "–" : `${Math.round(n)}%`;
  },
  duration(seconds: number) {
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
  },
  ago(unixSeconds: number) {
    return fmt.duration(Math.max(0, Date.now() / 1000 - unixSeconds)) + " ago";
  },
};
