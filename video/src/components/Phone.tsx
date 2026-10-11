import React from "react";
import { OffthreadVideo, Sequence, staticFile, useCurrentFrame } from "remotion";
import { C, deepShadow, FPS } from "../tokens";

// iPhone Air screen ratio (1260 × 2736).
export const SCREEN_RATIO = 1260 / 2736;

export type Seg = { clip: string; from: number; to: number; rate?: number };

/** Plays a list of footage segments back to back, filling `frames`. Rates stretch to fit unless fixed. */
export const ScreenVideo: React.FC<{ segs: Seg[]; frames: number; width: number }> = ({ segs, frames, width }) => {
  const height = width / SCREEN_RATIO;
  const srcLen = segs.reduce((a, s) => a + (s.to - s.from) / (s.rate ?? 1), 0);
  const k = srcLen / (frames / FPS); // global stretch so the segments exactly fill the scene
  let at = 0;
  return (
    <div style={{ position: "absolute", inset: 0, width, height, background: C.paper }}>
      {segs.map((s, i) => {
        const rate = (s.rate ?? 1) * k;
        const len = Math.round(((s.to - s.from) / rate) * FPS);
        const from = at;
        at += len;
        return (
          <Sequence key={i} from={from} durationInFrames={i === segs.length - 1 ? Math.max(1, frames - from) : len} layout="none">
            <OffthreadVideo
              src={staticFile(`clips/${s.clip}.mp4`)}
              trimBefore={Math.round(s.from * FPS)}
              playbackRate={rate}
              muted
              style={{ position: "absolute", inset: 0, width, height }}
            />
          </Sequence>
        );
      })}
    </div>
  );
};

/** Device frame. Children render inside the screen (same coordinate box as ScreenVideo). */
export const Phone: React.FC<{ width: number; children: React.ReactNode; style?: React.CSSProperties; shadow?: boolean }> = ({
  width, children, style, shadow = true,
}) => {
  const height = width / SCREEN_RATIO;
  const bezel = width * 0.035;
  const r = width * 0.16;
  return (
    <div
      style={{
        position: "absolute",
        width: width + bezel * 2,
        height: height + bezel * 2,
        borderRadius: r + bezel,
        background: "#1d1c1a",
        boxShadow: shadow ? `${deepShadow}, inset 0 0 0 ${bezel * 0.18}px #4a4844` : undefined,
        ...style,
      }}
    >
      <div style={{ position: "absolute", left: bezel, top: bezel, width, height, borderRadius: r, overflow: "hidden", background: C.paper }}>
        {children}
      </div>
    </div>
  );
};

/** Magnifier: shows the same footage zoomed around (u, v) (0..1 screen coords). */
export const Lens: React.FC<{ segs: Seg[]; frames: number; screenW: number; u: number; v: number; zoom: number; size: number; offsetFrames?: number }> = ({
  segs, frames, screenW, u, v, zoom, size, offsetFrames = 0,
}) => {
  const w = screenW * zoom;
  const h = w / SCREEN_RATIO;
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", borderRadius: size }}>
      <div style={{ position: "absolute", left: size / 2 - u * w, top: size / 2 - v * h, width: w, height: h }}>
        <Sequence from={-offsetFrames} layout="none">
          <ScreenVideo segs={segs} frames={frames} width={w} />
        </Sequence>
      </div>
    </div>
  );
};

export const useLocal = () => useCurrentFrame();
