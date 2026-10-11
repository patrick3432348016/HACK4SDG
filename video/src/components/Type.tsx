import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C, F, paperShadow } from "../tokens";

/** Paper background with a faint fibre texture. */
export const PaperBg: React.FC<{ color?: string }> = ({ color = C.paper }) => (
  <AbsoluteFill style={{ background: color }}>
    <svg width="100%" height="100%" style={{ position: "absolute", inset: 0, opacity: 0.35, mixBlendMode: "multiply" }}>
      <filter id="fibre">
        <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="4" />
        <feColorMatrix values="0 0 0 0 0.45  0 0 0 0 0.38  0 0 0 0 0.3  0 0 0 0.10 0" />
      </filter>
      <rect width="100%" height="100%" filter="url(#fibre)" />
    </svg>
  </AbsoluteFill>
);

/**
 * Word-by-word reveal. Wrap a word in *asterisks* to colour it orange, or _underscores_ for green.
 */
export const Kinetic: React.FC<{
  text: string;
  at?: number;
  size?: number;
  serif?: boolean;
  color?: string;
  stagger?: number;
  weight?: number;
  lineHeight?: number;
  style?: React.CSSProperties;
  out?: number; // frame to fade out
}> = ({ text, at = 0, size = 64, serif = true, color = C.ink, stagger = 3, weight = 500, lineHeight = 1.12, style, out }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const words = text.split(" ");
  const fade = out !== undefined ? interpolate(frame, [out, out + 10], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }) : 1;
  return (
    <div style={{ fontFamily: serif ? F.serif : F.sans, fontSize: size, fontWeight: weight, lineHeight, color, letterSpacing: serif ? "-0.01em" : 0, opacity: fade, ...style }}>
      {words.map((w, i) => {
        if (w === "/") return <br key={i} />;
        const p = spring({ frame: frame - at - i * stagger, fps, config: { damping: 16, stiffness: 140, mass: 0.6 } });
        const hl = w.startsWith("*") ? C.orange : w.startsWith("_") ? C.green : undefined;
        const clean = w.replace(/[*_]/g, "");
        return (
          <span key={i} style={{ display: "inline-block", overflow: "hidden", verticalAlign: "top", paddingBottom: size * 0.08, marginBottom: -size * 0.08 }}>
            <span style={{ display: "inline-block", transform: `translateY(${(1 - p) * 100}%)`, opacity: p, color: hl }}>
              {clean}
              {i < words.length - 1 && words[i + 1] !== "/" ? " " : ""}
            </span>
          </span>
        );
      })}
    </div>
  );
};

/** Small label like "04 · BUMP TO CONNECT". */
export const Eyebrow: React.FC<{ n?: string; label: string; at?: number; color?: string }> = ({ n, label, at = 0, color = C.orange }) => {
  const frame = useCurrentFrame();
  const o = interpolate(frame, [at, at + 12], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const wLine = interpolate(frame, [at, at + 20], [0, 56], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 16, opacity: o, fontFamily: F.sans, fontSize: 22, fontWeight: 600, letterSpacing: "0.14em", color }}>
      {n && <span style={{ fontFamily: F.serif, fontSize: 26, letterSpacing: 0 }}>{n}</span>}
      <span style={{ width: wLine, height: 2, background: color, display: "inline-block" }} />
      <span>{label.toUpperCase()}</span>
    </div>
  );
};

/** Paper card that springs in. */
export const Card: React.FC<{ at?: number; style?: React.CSSProperties; children: React.ReactNode; from?: "up" | "left" | "right"; bg?: string }> = ({
  at = 0, style, children, from = "up", bg = "#fff",
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - at, fps, config: { damping: 15, stiffness: 120, mass: 0.7 } });
  const dx = from === "left" ? -40 : from === "right" ? 40 : 0;
  const dy = from === "up" ? 40 : 0;
  return (
    <div
      style={{
        position: "absolute",
        background: bg,
        borderRadius: 22,
        boxShadow: paperShadow,
        padding: "22px 28px",
        opacity: Math.min(1, p * 1.4),
        transform: `translate(${(1 - p) * dx}px, ${(1 - p) * dy}px) rotate(${(1 - p) * -1.5}deg)`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

/** Counts a number up. */
export const CountUp: React.FC<{ to: number; at: number; dur?: number; format?: (n: number) => string; style?: React.CSSProperties }> = ({
  to, at, dur = 40, format = (n) => Math.round(n).toLocaleString("en-US"), style,
}) => {
  const frame = useCurrentFrame();
  const t = interpolate(frame, [at, at + dur], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: (x) => 1 - Math.pow(1 - x, 4) });
  return <span style={style}>{format(to * t)}</span>;
};

/** Chinese UI phrase → English meaning, the visual "translation" used on every app shot. */
export const Translate: React.FC<{ zh: string; en: string; tone?: "orange" | "green" | "amber" | "plain" }> = ({ zh, en, tone = "plain" }) => {
  const zhColor = tone === "green" ? C.greenInk : tone === "orange" ? C.orangeDeep : tone === "amber" ? "#854F0B" : C.ink2;
  return (
    <div style={{ fontFamily: F.sans }}>
      <div style={{ fontFamily: F.zh, fontSize: 24, color: zhColor, marginBottom: 6 }}>{zh}</div>
      <div style={{ fontSize: 28, color: C.ink, lineHeight: 1.25, fontWeight: 500 }}>{en}</div>
    </div>
  );
};
