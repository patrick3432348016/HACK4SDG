import React from "react";
import { useCurrentFrame } from "remotion";
import { C } from "../tokens";
import { along, Block, IsoBlock, IsoPath, IsoSlab, IsoTree, Tree, useGrow, Walker } from "./Iso";

// The signature estate used in the opening, the insight and the close.
export const BLOCKS: Block[] = [
  { x: 2, y: 2, w: 3, d: 3, h: 9, kind: "home" },
  { x: 7, y: 1.5, w: 3, d: 3, h: 7.5, kind: "home" },
  { x: 12, y: 2, w: 3, d: 3, h: 8, kind: "home" },
  { x: 2, y: 8, w: 3, d: 3, h: 10, kind: "home" },
  { x: 2, y: 13.5, w: 3, d: 3, h: 11, kind: "home" },
  { x: 13, y: 8, w: 4, d: 2.5, h: 3, kind: "plain" },
  { x: 13, y: 12.5, w: 4, d: 4, h: 2, kind: "plain" },
  { x: 8, y: 14, w: 3, d: 2.4, h: 2.4, kind: "plain" },
  { x: 8.6, y: 8.6, w: 1.6, d: 1.6, h: 1.4, kind: "accent" }, // the pavilion
];
export const TREES: Tree[] = [
  { x: 6.5, y: 7 }, { x: 11.5, y: 7 }, { x: 6.5, y: 12 }, { x: 11.5, y: 11.8 }, { x: 17.6, y: 6.5 },
  { x: 18, y: 11 }, { x: 0.8, y: 6.5 }, { x: 0.8, y: 12 }, { x: 5.8, y: 17.5 }, { x: 12, y: 17.6 }, { x: 16.2, y: 4.8 },
];
// Footpaths that walkers share.
export const PATHS: [number, number][][] = [
  [[6, 0.5], [6, 6.2], [12, 6.2], [12, 12.4], [6.2, 12.4], [6.2, 6.4]],
  [[0.5, 6.5], [6, 6.5], [9.4, 9.4], [12.3, 12.6], [18.5, 12.6]],
  [[6.2, 18.5], [6.2, 12.5], [9.4, 9.4], [12.2, 6.2], [18.5, 6.2]],
];

export const Estate: React.FC<{
  s: number;
  growAt?: number;
  pathsAt?: number;
  walkersAt?: number;
  walkerCount?: number;
  meet?: number; // 0..1 walkers turn green and link up
  hideBlocks?: boolean;
}> = ({ s, growAt = 0, pathsAt = 9999, walkersAt = 9999, walkerCount = 6, meet = 0, hideBlocks }) => {
  const frame = useCurrentFrame();
  const slab = useGrow(growAt - 6, 18);
  const order = [...BLOCKS].map((b, i) => ({ b, i })).sort((a, z) => a.b.x + a.b.y - (z.b.x + z.b.y));
  const pathGrow = Math.max(0, Math.min(1, (frame - pathsAt) / 40));
  const walkers = Array.from({ length: walkerCount }).map((_, i) => {
    const path = PATHS[i % PATHS.length];
    const speed = 0.0035 + (i % 3) * 0.0011;
    const f = ((frame - walkersAt) * speed + i * 0.17) % 1;
    const [gx, gy] = along(path, Math.max(0, f));
    return { gx, gy, i, on: frame > walkersAt + i * 6 };
  });
  return (
    <g>
      <g transform={`scale(${0.92 + 0.08 * slab})`} opacity={slab}>
        <IsoSlab x={-0.5} y={-0.5} w={20} d={20} s={s} />
      </g>
      {PATHS.map((p, i) => (
        <IsoPath key={i} path={p} s={s} progress={pathGrow} color={C.line} width={0.55} />
      ))}
      {meet > 0 && (
        <IsoPath path={PATHS[1]} s={s} progress={meet} color={C.orange} width={0.18} />
      )}
      {TREES.map((t, i) => (
        <TreeGrow key={i} t={t} s={s} delay={growAt + 18 + i * 2} />
      ))}
      {!hideBlocks && order.map(({ b, i }) => <BlockGrow key={i} b={b} s={s} delay={growAt + 6 + i * 4} />)}
      {walkers.filter((w) => w.on).map((w) => (
        <Walker key={w.i} gx={w.gx} gy={w.gy} s={s} scale={1.1} bob={(frame + w.i * 7) * 0.35}
          color={meet > 0.5 && w.i < 2 ? C.green : w.i === 0 ? C.orange : meet > 0 ? C.grey : w.i % 2 ? C.grey : "#9C9A92"} />
      ))}
    </g>
  );
};

const BlockGrow: React.FC<{ b: Block; s: number; delay: number }> = ({ b, s, delay }) => {
  const g = useGrow(delay, 12);
  return <IsoBlock b={b} s={s} grow={g} />;
};
const TreeGrow: React.FC<{ t: Tree; s: number; delay: number }> = ({ t, s, delay }) => {
  const g = useGrow(delay, 10);
  return <IsoTree t={t} s={s} grow={g} />;
};
