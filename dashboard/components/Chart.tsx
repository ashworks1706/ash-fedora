"use client";

import { useId } from "react";

type Series = { values: (number | null)[]; color: string; label?: string };

/** Minimal area chart. `max` fixes the scale (e.g. 100 for percentages); otherwise
 *  it follows the data. Gaps (null) break the line. */
export function Chart({ series, max, height = 72 }: { series: Series[]; max?: number; height?: number }) {
  const id = useId();
  const W = 300;
  const H = height;
  const n = Math.max(2, ...series.map((s) => s.values.length));
  const peak = max ?? Math.max(1, ...series.flatMap((s) => s.values.filter((v): v is number => v != null))) * 1.15;
  const x = (i: number) => (i / (n - 1)) * W;
  const y = (v: number) => H - (Math.min(v, peak) / peak) * (H - 2) - 1;

  return (
    <svg className="chart" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" role="img"
         aria-label={series.map((s) => s.label).filter(Boolean).join(", ")}>
      {[0.25, 0.5, 0.75].map((f) => (
        <line key={f} x1="0" x2={W} y1={H * f} y2={H * f} stroke="var(--line)" strokeWidth="1"
              vectorEffect="non-scaling-stroke" />
      ))}
      {series.map((s, si) => {
        const offset = n - s.values.length;
        const segments: string[][] = [[]];
        s.values.forEach((v, i) => {
          if (v == null) segments.push([]);
          else segments[segments.length - 1].push(`${x(i + offset).toFixed(1)},${y(v).toFixed(1)}`);
        });
        const grad = `${id}-g${si}`;
        return (
          <g key={si}>
            <defs>
              <linearGradient id={grad} x1="0" x2="0" y1="0" y2="1">
                <stop offset="0%" stopColor={s.color} stopOpacity="0.22" />
                <stop offset="100%" stopColor={s.color} stopOpacity="0" />
              </linearGradient>
            </defs>
            {segments.filter((p) => p.length > 1).map((pts, k) => {
              const first = pts[0].split(",")[0];
              const last = pts[pts.length - 1].split(",")[0];
              return (
                <g key={k}>
                  <path d={`M${first},${H} L${pts.join(" L")} L${last},${H} Z`} fill={`url(#${grad})`} />
                  <polyline points={pts.join(" ")} fill="none" stroke={s.color} strokeWidth="1.5"
                            vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
                </g>
              );
            })}
          </g>
        );
      })}
    </svg>
  );
}
