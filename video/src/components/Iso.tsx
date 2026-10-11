import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "../tokens";

// Paper-cut isometric estate, drawn in SVG so it can grow, fold and be walked through.
const COS = Math.cos(Math.PI / 6);
const SIN = 0.5;
export const iso = (gx: number, gy: number, z = 0, s = 1) => [(gx - gy) * COS * s, (gx + gy) * SIN * s - z * s] as const;
const pts = (a: (readonly [number, number])[]) => a.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(" ");

export type Block = { x: number; y: number; w: number; d: number; h: number; kind?: "home" | "plain" | "accent"; delay?: number };
export type Tree = { x: number; y: number; r?: number; delay?: number };

const FACES = {
  home: [C.roofA, C.roofC, C.roofB],
  plain: [C.paper2, "#E2E0D9", "#ECEAE4"],
  accent: ["#F3B9A0", C.orange, "#E57A52"],
};

export const IsoBlock: React.FC<{ b: Block; s: number; grow: number }> = ({ b, s, grow }) => {
  const h = Math.max(0.0001, b.h * grow);
  const [top, left, right] = FACES[b.kind ?? "plain"];
  const P = (gx: number, gy: number, z: number) => iso(gx, gy, z, s);
  const { x, y, w, d } = b;
  return (
    <g opacity={grow > 0.001 ? 1 : 0}>
      <polygon points={pts([P(x, y + d, 0), P(x + w, y + d, 0), P(x + w, y + d, h), P(x, y + d, h)])} fill={left} />
      <polygon points={pts([P(x + w, y, 0), P(x + w, y + d, 0), P(x + w, y + d, h), P(x + w, y, h)])} fill={right} />
      <polygon points={pts([P(x, y, h), P(x + w, y, h), P(x + w, y + d, h), P(x, y + d, h)])} fill={top} />
      {/* window rhythm on the left face: tiny paper slits */}
      {b.kind === "home" && h > 3 &&
        Array.from({ length: Math.floor(h / 1.6) }).map((_, i) => {
          const z = 1 + i * 1.6;
          return <polyline key={i} points={pts([P(x + w * 0.2, y + d, z), P(x + w * 0.8, y + d, z)])} stroke={C.roofB} strokeWidth={s * 0.18} />;
        })}
    </g>
  );
};

export const IsoTree: React.FC<{ t: Tree; s: number; grow: number }> = ({ t, s, grow }) => {
  const [cx, cy] = iso(t.x, t.y, 0, s);
  const r = (t.r ?? 0.7) * s * grow;
  return (
    <g>
      <ellipse cx={cx} cy={cy} rx={r * 1.1} ry={r * 0.45} fill="rgba(80,70,50,0.08)" />
      <circle cx={cx} cy={cy - r * 0.9} r={r} fill={C.tree} />
      <circle cx={cx - r * 0.35} cy={cy - r * 1.15} r={r * 0.55} fill={C.treeDark} opacity={0.7} />
    </g>
  );
};

/** Ground slab like the app's diorama base. */
export const IsoSlab: React.FC<{ x: number; y: number; w: number; d: number; s: number; t?: number; fill?: string }> = ({ x, y, w, d, s, t = 1.2, fill = C.paper }) => {
  const P = (gx: number, gy: number, z: number) => iso(gx, gy, z, s);
  return (
    <g>
      <polygon points={pts([P(x, y + d, 0), P(x + w, y + d, 0), P(x + w, y + d, -t), P(x, y + d, -t)])} fill="#E8E5DD" />
      <polygon points={pts([P(x + w, y, 0), P(x + w, y + d, 0), P(x + w, y + d, -t), P(x + w, y, -t)])} fill="#F0EEE8" />
      <polygon points={pts([P(x, y, 0), P(x + w, y, 0), P(x + w, y + d, 0), P(x, y + d, 0)])} fill={fill} />
    </g>
  );
};

/** A path on the ground (grid coords), drawn progressively. */
export const IsoPath: React.FC<{ path: [number, number][]; s: number; progress: number; color?: string; width?: number; dash?: boolean }> = ({
  path, s, progress, color = C.line, width = 0.5, dash,
}) => {
  const p2 = path.map(([a, b]) => iso(a, b, 0, s));
  let len = 0;
  for (let i = 1; i < p2.length; i++) len += Math.hypot(p2[i][0] - p2[i - 1][0], p2[i][1] - p2[i - 1][1]);
  return (
    <polyline
      points={pts(p2)}
      fill="none"
      stroke={color}
      strokeWidth={width * s}
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeDasharray={dash ? `${s * 0.4} ${s * 0.6}` : `${len} ${len}`}
      strokeDashoffset={dash ? 0 : len * (1 - progress)}
      opacity={dash ? progress : 1}
    />
  );
};

/** Position along a grid path at fraction f. */
export const along = (path: [number, number][], f: number): [number, number] => {
  const seg: number[] = [];
  let total = 0;
  for (let i = 1; i < path.length; i++) {
    const l = Math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]);
    seg.push(l);
    total += l;
  }
  let t = Math.max(0, Math.min(1, f)) * total;
  for (let i = 0; i < seg.length; i++) {
    if (t <= seg[i]) {
      const k = seg[i] ? t / seg[i] : 0;
      return [path[i][0] + (path[i + 1][0] - path[i][0]) * k, path[i][1] + (path[i + 1][1] - path[i][1]) * k];
    }
    t -= seg[i];
  }
  return path[path.length - 1];
};

/** A little paper walker: orange (you), green (neighbour) or grey (stranger). */
export const Walker: React.FC<{ gx: number; gy: number; s: number; color?: string; scale?: number; bob?: number }> = ({ gx, gy, s, color = C.orange, scale = 1, bob = 0 }) => {
  const [x, y] = iso(gx, gy, 0, s);
  const k = s * 0.38 * scale;
  return (
    <g transform={`translate(${x},${y - Math.abs(Math.sin(bob)) * k * 0.25})`}>
      <ellipse cx={0} cy={k * 0.1} rx={k * 0.9} ry={k * 0.35} fill="rgba(80,60,40,0.12)" />
      <rect x={-k * 0.42} y={-k * 2.0} width={k * 0.84} height={k * 1.5} rx={k * 0.42} fill={color} />
      <circle cx={0} cy={-k * 2.55} r={k * 0.5} fill={color} />
    </g>
  );
};

/** Grow helper: spring from 0→1 starting at `delay` frames. */
export const useGrow = (delay: number, damping = 14) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping, stiffness: 120, mass: 0.7 } });
};

export const ease = (frame: number, a: number, b: number, from = 0, to = 1) =>
  interpolate(frame, [a, b], [from, to], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: (t) => 1 - Math.pow(1 - t, 3) });
