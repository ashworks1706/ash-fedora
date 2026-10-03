"use client";

import { useState } from "react";
import { Chart } from "./Chart";
import { fmt, serviceAction, type Info, type Metrics, type Now, type Point, type Service } from "@/lib/api";

const host = () => (typeof window === "undefined" ? "" : window.location.hostname);
const series = (h: Point[], key: keyof Point) => h.map((p) => (p[key] as number | null) ?? null);

function SectionHead({ id, title, hint }: { id?: string; title: string; hint?: string }) {
  return (
    <div className="section-head" id={id}>
      <h2>{title}</h2>
      {hint && <span className="hint">{hint}</span>}
    </div>
  );
}

/* ------------------------------------------------------------------ services */

function ServiceCard({ s, onChange }: { s: Service; onChange: () => void }) {
  const [busy, setBusy] = useState(false);
  const url = s.port ? `https://${host()}:${s.port}` : null;
  const toggle = async () => {
    const action = s.active ? "stop" : "start";
    if (action === "stop" && !confirm(`Stop ${s.name}?`)) return;
    setBusy(true);
    await serviceAction(s.id, action);
    setTimeout(() => { setBusy(false); onChange(); }, 700);
  };
  const live = s.public ? "warn" : "ok";
  return (
    <div className="card">
      <div className="card-head">
        <span className="card-title"><span className={`dot ${s.active ? live : ""}`} />{s.name}</span>
        {s.public ? <span className="badge public">public</span>
          : s.port ? <span className="badge mono">:{s.port}</span>
          : <span className="badge">Moonlight app</span>}
      </div>
      <div className="card-desc">{s.desc}</div>
      <div className="card-foot">
        <span className="mono" style={{ color: "var(--faint)", fontSize: 12 }}>
          {s.active ? (s.public ? "sharing publicly" : "running") : s.public ? "not shared" : "stopped"}
          {s.local ? ` · local ${s.local}` : ""}
        </span>
        <span className="btns">
          {url && !s.public && (
            <a className={`btn primary${s.active ? "" : " disabled"}`} href={s.active ? url : undefined}
               target="_blank" rel="noreferrer" aria-disabled={!s.active}
               style={s.active ? undefined : { opacity: 0.4, pointerEvents: "none" }}>Open</a>
          )}
          {(!s.public || s.active) && (
            <button className={`btn${s.active ? " danger" : ""}`} disabled={busy} onClick={toggle}>
              {busy ? "…" : s.active ? (s.public ? "Stop sharing" : "Stop") : "Start"}
            </button>
          )}
        </span>
      </div>
    </div>
  );
}

export function Services({ info, onChange }: { info: Info | null; onChange: () => void }) {
  return (
    <section>
      <SectionHead id="services" title="Services" hint="tailnet only unless marked public" />
      <div className="grid g-services">
        {info ? info.services.map((s) => <ServiceCard key={s.id} s={s} onChange={onChange} />)
          : <div className="card skeleton">Loading services…</div>}
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ metrics */

function MetricCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="card">
      <div className="card-head"><span className="card-desc">{title}</span></div>
      {children}
    </div>
  );
}

function Legend({ items }: { items: [string, string][] }) {
  return (
    <div className="legend">
      {items.map(([label, color]) => <span key={label}><i style={{ background: color }} />{label}</span>)}
    </div>
  );
}

export function MetricsGrid({ m, info }: { m: Metrics | null; info: Info | null }) {
  const now = (m?.now ?? {}) as Partial<Now>;
  const h = m?.history ?? [];
  const times = h.map((p) => p.t);
  if (!m || now.cpu == null) {
    return (
      <section>
        <SectionHead id="metrics" title="System" />
        <div className="card skeleton">Collecting samples…</div>
      </section>
    );
  }
  const nv = now.nvidia ?? { state: "unknown" };
  const ig = now.igpu_detail;
  const temps = now.temps ?? {};
  const bat = now.battery;
  const disk = now.disk;

  return (
    <section>
      <SectionHead id="metrics" title="System" hint="last 10 minutes · live every 2 s while open" />
      <div className="grid g-metrics">
        <MetricCard title="CPU">
          <div className="metric-value mono">{fmt.pct(now.cpu)}<small>{info?.cores ?? ""} threads</small></div>
          <div className="cores" aria-label="per-core usage">
            {(now.cores ?? []).map((c, i) => <div key={i} className="core"><span style={{ height: `${c}%` }} /></div>)}
          </div>
          <Chart times={times} series={[{ values: series(h, "cpu"), color: "var(--c1)", label: "CPU" }]} max={100} />
          <div className="metric-row mono">
            load <b>{now.load?.map((l) => l.toFixed(2)).join(" ")}</b>
          </div>
        </MetricCard>

        <MetricCard title="Memory">
          <div className="metric-value mono">
            {fmt.bytes(now.mem_used ?? 0)}<small>/ {fmt.bytes(now.mem_total ?? 0, 0)}</small>
          </div>
          <Chart times={times} series={[{ values: series(h, "mem"), color: "var(--c2)", label: "Memory" },
                          { values: series(h, "swap"), color: "var(--c4)", label: "Swap" }]} max={100} />
          <Legend items={[[`RAM ${fmt.pct(now.mem)}`, "var(--c2)"],
                          [`Swap ${fmt.bytes(now.swap_used ?? 0)}`, "var(--c4)"]]} />
        </MetricCard>

        <MetricCard title="Network">
          <div className="metric-value mono">
            ↓ {fmt.rate(now.rx ?? 0)}<small>↑ {fmt.rate(now.tx ?? 0)}</small>
          </div>
          <Chart times={times} series={[{ values: series(h, "rx"), color: "var(--c3)", label: "Download" },
                          { values: series(h, "tx"), color: "var(--c1)", label: "Upload" }]} />
          <Legend items={[["Download", "var(--c3)"], ["Upload", "var(--c1)"]]} />
        </MetricCard>

        <MetricCard title="GPU">
          <div className="metric-value mono">
            {fmt.pct(ig?.util)}<small>Radeon 780M</small>
          </div>
          <Chart times={times} series={[{ values: series(h, "igpu"), color: "var(--c2)", label: "iGPU" },
                          { values: series(h, "dgpu"), color: "var(--c3)", label: "dGPU" }]} max={100} />
          <div className="metric-row mono">
            <span>VRAM <b>{ig ? `${fmt.bytes(ig.mem_used * 2 ** 20, 0)} / ${fmt.bytes(ig.mem_total * 2 ** 20, 0)}` : "–"}</b></span>
            <span>
              NVIDIA <b>{nv.state === "suspended" ? "sleeping"
                : nv.util != null ? `${fmt.pct(nv.util)} · ${nv.temp}°C · ${nv.power ?? "–"} W`
                : nv.state}</b>
            </span>
          </div>
        </MetricCard>

        <MetricCard title="Thermals & power">
          <div className="metric-value mono">
            {temps.k10temp != null ? `${Math.round(temps.k10temp)}°C` : "–"}<small>CPU</small>
          </div>
          <Chart times={times} series={[{ values: series(h, "temp_cpu"), color: "var(--c4)", label: "CPU °C" },
                          { values: series(h, "temp_gpu"), color: "var(--c2)", label: "GPU °C" }]} max={100} />
          <div className="metric-row mono">
            <span>GPU <b>{temps.amdgpu != null ? `${Math.round(temps.amdgpu)}°C` : "–"}</b></span>
            <span>SSD <b>{temps.nvme != null ? `${Math.round(temps.nvme)}°C` : "–"}</b></span>
            <span>Fans <b>{now.fans?.length ? now.fans.join(" / ") + " rpm" : "–"}</b></span>
          </div>
          {bat && (
            <div className="metric-row mono">
              <span>Battery <b>{bat.percent}%</b> {bat.plugged ? "· plugged in" : "· on battery"}
                {bat.secs_left ? ` · ${fmt.duration(bat.secs_left)} left` : ""}</span>
            </div>
          )}
        </MetricCard>

        <MetricCard title="Disk">
          <div className="metric-value mono">
            {disk ? fmt.bytes(disk.used, 0) : "–"}<small>/ {disk ? fmt.bytes(disk.total, 0) : "–"}</small>
          </div>
          <div className="bar"><span style={{ width: `${disk?.percent ?? 0}%` }} /></div>
          <Chart times={times} series={[{ values: series(h, "disk_r"), color: "var(--c3)", label: "Read" },
                          { values: series(h, "disk_w"), color: "var(--c4)", label: "Write" }]} />
          <Legend items={[[`Read ${fmt.rate(now.disk_r ?? 0)}`, "var(--c3)"],
                          [`Write ${fmt.rate(now.disk_w ?? 0)}`, "var(--c4)"]]} />
        </MetricCard>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ processes, sessions, devices */

export function Activity({ m, info }: { m: Metrics | null; info: Info | null }) {
  return (
    <section>
      <div className="grid g-two">
        <div>
          <SectionHead id="processes" title="Processes" hint="top by CPU" />
          <div className="card flush">
            <table className="table mono">
              <thead>
                <tr><th>PID</th><th>Name</th><th>User</th><th className="r">CPU</th><th className="r">Memory</th></tr>
              </thead>
              <tbody>
                {(m?.procs ?? []).map((p) => (
                  <tr key={p.pid}>
                    <td style={{ color: "var(--faint)" }}>{p.pid}</td>
                    <td className="name">{p.name}</td>
                    <td style={{ color: "var(--muted)" }}>{p.user}</td>
                    <td className="r">{p.cpu.toFixed(1)}%</td>
                    <td className="r">{fmt.bytes(p.rss, 0)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        <div>
          <SectionHead id="sessions" title="tmux sessions" hint="t NAME to attach" />
          <div className="card flush list">
            {info?.tmux.length ? info.tmux.map((s) => (
              <div className="list-row" key={s.name}>
                <span className="mono"><span className={`dot ${s.attached ? "ok" : ""}`}
                  style={{ display: "inline-block", marginRight: 8 }} />{s.name}</span>
                <span className="meta">{s.windows} win · {s.attached ? `${s.attached} attached` : "detached"} · {fmt.ago(s.activity)}</span>
              </div>
            )) : <div className="list-row meta">No sessions</div>}
          </div>
          <SectionHead id="devices" title="Devices" hint="Tailscale" />
          <div className="card flush list">
            {info?.tailscale.peers.map((p) => (
              <div className="list-row" key={p.name}>
                <span><span className={`dot ${p.online ? "ok" : ""}`}
                  style={{ display: "inline-block", marginRight: 8 }} />{p.name}</span>
                <span className="meta mono">{p.os} · {p.ip}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ commands */

function Cmd({ text, note }: { text: string; note: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button className="cmd mono" onClick={async () => {
      try { await navigator.clipboard.writeText(text); setCopied(true); setTimeout(() => setCopied(false), 1400); } catch {}
    }}>
      <span className="prompt">$</span>
      <span className="text">{text}</span>
      <span className={`note${copied ? " copied" : ""}`}>{copied ? "copied" : note}</span>
    </button>
  );
}

export function Commands({ info }: { info: Info | null }) {
  const [port, setPort] = useState("");
  const user = info?.user || "user";
  const name = info?.hostname || "host";
  return (
    <section>
      <div className="grid g-two">
        <div>
          <SectionHead id="commands" title="Commands" hint="click to copy" />
          <div className="term">
            <div className="term-bar"><i /><i /><i /><span className="mono">from your Mac or iPhone</span></div>
            <Cmd text={`ssh -t ${user}@${name} t`} note="pick a tmux session" />
            <Cmd text={`ssh -N -L 8000:localhost:8000 ${user}@${name}`} note="tunnel a local-only port" />
            <Cmd text={`scp FILE ${user}@${name}:~/Downloads/`} note="send a file" />
            <Cmd text={`scp ${user}@${name}:~/PATH ~/Desktop/`} note="fetch a file" />
            <Cmd text={`rsync -avz DIR/ ${user}@${name}:~/DIR/`} note="sync a folder" />
          </div>
          <div className="term" style={{ marginTop: 12 }}>
            <div className="term-bar"><i /><i /><i /><span className="mono">on the laptop</span></div>
            <Cmd text="demo 3000" note="public link for a dev server" />
            <Cmd text="t work" note="join or create a session" />
            <Cmd text="remote-off" note="turn all remote access off" />
            <Cmd text="remote-on" note="turn it back on" />
          </div>
        </div>
        <div>
          <SectionHead id="preview" title="Preview a dev server" />
          <form className="card" onSubmit={(e) => {
            e.preventDefault();
            if (/^\d{2,5}$/.test(port)) window.open(`http://${name}:${port}`, "_blank");
          }}>
            <div className="card-desc">
              Start it with <span className="mono">--host</span> (Vite) or <span className="mono">-H 0.0.0.0</span> (Next.js),
              then open it from any of your devices.
            </div>
            <div className="btns">
              <input className="input mono" inputMode="numeric" placeholder="3000" value={port}
                     onChange={(e) => setPort(e.target.value.trim())} aria-label="Port" />
              <button className="btn primary" type="submit">Open</button>
            </div>
          </form>
          <SectionHead title="Files" />
          <div className="card">
            <p className="card-desc" style={{ margin: 0 }}>
              Share from iPhone or Mac → <b>Tailscale</b> → <b>{name}</b>. Files land in{" "}
              <span className="mono">~/Downloads</span>. Paste or drop images into the web terminal to
              hand them to Claude Code.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ docs */

const DOCS: [string, string, string][] = [
  ["Setup guide", "https://github.com/ashworks1706/ash-fedora/blob/main/docs/REMOTE.md", "How this dashboard and remote access are set up"],
  ["Project repo", "https://github.com/ashworks1706/ash-fedora", "Configs, scripts and installer"],
  ["Tailscale Serve & Funnel", "https://tailscale.com/kb/1312/serve", "Private HTTPS addresses and public links"],
  ["Tailscale SSH", "https://tailscale.com/kb/1193/tailscale-ssh", "Key-less SSH between your devices"],
  ["Taildrop", "https://tailscale.com/kb/1106/taildrop", "Send files between devices"],
  ["Sunshine", "https://docs.lizardbyte.dev/projects/sunshine/", "Game-stream host behind Moonlight"],
  ["Moonlight", "https://moonlight-stream.org", "Low-latency desktop streaming clients"],
  ["Moonlight Web", "https://github.com/MrCreativ3001/moonlight-web-stream", "Moonlight in the browser"],
  ["code-server", "https://coder.com/docs/code-server", "VS Code in the browser"],
  ["ttyd", "https://github.com/tsl0922/ttyd", "Terminal in the browser"],
  ["tmux", "https://github.com/tmux/tmux/wiki", "Sessions that survive disconnects"],
  ["Hyprland", "https://wiki.hypr.land", "The compositor this all runs on"],
];

export function Docs() {
  return (
    <section>
      <SectionHead id="docs" title="Docs" />
      <div className="grid docs">
        {DOCS.map(([title, href, desc]) => (
          <a key={title} className="card doc" href={href} target="_blank" rel="noreferrer">
            <span className="card-head"><span className="card-title">{title}</span><span className="arrow">↗</span></span>
            <span className="card-desc">{desc}</span>
          </a>
        ))}
      </div>
    </section>
  );
}
