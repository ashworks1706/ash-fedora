"use client";

import { Activity, Commands, Docs, MetricsGrid, Services } from "@/components/sections";
import { fmt, usePoll, type Info, type Metrics } from "@/lib/api";

export default function Page() {
  const info = usePoll<Info>("/api/info", 10_000);
  const metrics = usePoll<Metrics>("/api/metrics", 2_000);
  const i = info.data;
  const up = i ? fmt.duration(Date.now() / 1000 - i.boot_time) : "–";
  const running = i?.services.filter((s) => s.active && !s.public).length ?? 0;
  const publicLive = i?.services.some((s) => s.public && s.active);

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner">
          <span className="brand">
            <span className="brand-mark mono">~</span>
            <span className="mono">{i?.hostname ?? "…"}</span>
            <span className="crumb">/</span>
            <span style={{ color: "var(--muted)", fontWeight: 400 }}>dashboard</span>
          </span>
          <span className="spacer" />
          <nav className="topnav">
            {["services", "metrics", "processes", "commands", "docs"].map((s) => (
              <a key={s} href={`#${s}`}>{s[0].toUpperCase() + s.slice(1)}</a>
            ))}
          </nav>
        </div>
      </header>

      <main className="wrap">
        {(info.error || metrics.error) && (
          <div className="banner">Can&apos;t reach the dashboard API ({info.error || metrics.error}). Is
            <span className="mono"> dashboard-api.service</span> running?</div>
        )}

        <div className="hero">
          <div>
            <h1>{i?.hostname ?? "Loading…"}</h1>
            <div className="sub">{i ? `${i.os} · ${i.cpu}` : " "}</div>
          </div>
          <div className="facts mono">
            <span className="fact">up <b>{up}</b></span>
            <span className="fact">kernel <b>{i?.kernel ?? "–"}</b></span>
            <span className="fact">tailnet <b>{i?.tailscale.ip ?? "–"}</b></span>
            <span className="fact">services <b>{running}</b> running</span>
            {publicLive && <span className="fact" style={{ color: "var(--warn)" }}>● public demo live</span>}
          </div>
        </div>

        <Services info={i} onChange={info.refresh} />
        <MetricsGrid m={metrics.data} info={i} />
        <Activity m={metrics.data} info={i} />
        <Commands info={i} />
        <Docs />
      </main>

      <footer>
        <div className="wrap mono">
          <span>{i?.tailscale.host ?? ""}</span>
          <span>private to your Tailscale devices · plugged in = always reachable</span>
        </div>
      </footer>
    </>
  );
}
