import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { featureIds, scene, SceneId } from "../timeline";
import { C, F, paperShadow } from "../tokens";
import { ease } from "./Iso";
import { Phone, ScreenVideo, SCREEN_RATIO, Seg } from "./Phone";
import { Eyebrow, Kinetic, PaperBg, Translate } from "./Type";

export type Callout = {
  at: number; // 0..1 of the scene (footage is stretched over the whole scene)
  u: number; // point on the phone screen, 0..1
  v: number;
  zh?: string;
  en: string;
  tone?: "orange" | "green" | "amber" | "plain";
};

export type FeatureConfig = {
  id: SceneId;
  label: string;
  title: string; // Kinetic syntax: *orange* _green_ and " / " line breaks
  segs: Seg[];
  side?: "left" | "right"; // where the phone sits
  callouts?: Callout[];
  overlay?: (p: { frame: number; dur: number; phone: { x: number; y: number; w: number; h: number } }) => React.ReactNode;
  phoneW?: number;
};

const SCREEN_W = 380;

export const FeatureScene: React.FC<{ cfg: FeatureConfig }> = ({ cfg }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = scene(cfg.id);
  const n = String(featureIds.indexOf(cfg.id) + 1).padStart(2, "0");
  const side = cfg.side ?? "right";
  const sw = cfg.phoneW ?? SCREEN_W;
  const sh = sw / SCREEN_RATIO;
  const bezel = sw * 0.035;
  const phoneX = side === "right" ? 1420 - sw / 2 : 500 - sw / 2;
  const phoneY = (1080 - sh) / 2 - bezel - 20;
  const textX = side === "right" ? 150 : 940;

  const enter = spring({ frame: frame - 4, fps, config: { damping: 18, stiffness: 90 } });
  const rot = interpolate(frame, [0, s.dur], [side === "right" ? -9 : 9, side === "right" ? -3 : 3]);
  const push = interpolate(frame, [0, s.dur], [0.98, 1.03]);

  const atFrame = (f: number) => Math.max(10, f * s.dur);
  const screen = { x: phoneX + bezel, y: phoneY + bezel, w: sw, h: sh };
  const callouts = cfg.callouts ?? [];

  return (
    <AbsoluteFill>
      <PaperBg />
      {/* soft roof-coloured shape behind the phone */}
      <div style={{
        position: "absolute", left: phoneX - 170, top: 110, width: sw + 340, height: 820, borderRadius: 400,
        background: C.roofA, opacity: 0.55 * enter, transform: `scale(${0.8 + 0.2 * enter})`,
      }} />
      <AbsoluteFill style={{ perspective: 2400 }}>
        <div style={{
          position: "absolute", inset: 0,
          transform: `translateX(${(1 - enter) * (side === "right" ? 260 : -260)}px) rotateY(${rot}deg) scale(${push})`,
          transformOrigin: `${phoneX + sw / 2}px 540px`, opacity: enter,
        }}>
          <Phone width={sw} style={{ left: phoneX, top: phoneY }}>
            <ScreenVideo segs={cfg.segs} frames={s.dur} width={sw} />
          </Phone>
          {/* numbered rings on the phone, shown while their moment is on screen */}
          <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, overflow: "visible" }}>
            {callouts.map((c, i) => {
              const from = atFrame(c.at);
              const until = Math.min(from + 80, i + 1 < callouts.length ? atFrame(callouts[i + 1].at) : 1e9);
              const t = ease(frame, from, from + 14) * (1 - ease(frame, until - 8, until));
              const cx = screen.x + c.u * sw;
              const cy = screen.y + c.v * sh;
              return (
                <g key={i} opacity={t}>
                  <circle cx={cx} cy={cy} r={30 + (1 - t) * 30} fill="rgba(216,90,48,0.10)" stroke={C.orange} strokeWidth={4} />
                  <circle cx={cx + 30} cy={cy - 30} r={17} fill={C.orange} />
                  <text x={cx + 30} y={cy - 24} textAnchor="middle" fontFamily={F.sans} fontSize={19} fontWeight={700} fill="#fff">{i + 1}</text>
                </g>
              );
            })}
          </svg>
        </div>
      </AbsoluteFill>

      <div style={{ position: "absolute", left: textX, top: 140, width: 860 }}>
        <Eyebrow n={n} label={cfg.label} at={6} />
        <div style={{ height: 26 }} />
        <Kinetic text={cfg.title} at={12} size={76} />
      </div>

      {callouts.map((c, i) => (
        <CalloutCard key={i} c={c} i={i} at={atFrame(c.at)} x={textX} />
      ))}

      {cfg.overlay?.({ frame, dur: s.dur, phone: screen })}

      <Progress current={cfg.id} />
    </AbsoluteFill>
  );
};

const CalloutCard: React.FC<{ c: Callout; i: number; at: number; x: number }> = ({ c, i, at, x }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - at, fps, config: { damping: 15, stiffness: 120 } });
  if (frame < at - 1) return null;
  const top = 430 + i * 145;
  return (
    <div style={{
      position: "absolute", left: x, top, width: 680, background: "#fff", borderRadius: 20, boxShadow: paperShadow,
      padding: "18px 26px 18px 76px", opacity: Math.min(1, p * 1.4), transform: `translateX(${(1 - p) * -30}px)`,
    }}>
      <div style={{
        position: "absolute", left: 22, top: 20, width: 36, height: 36, borderRadius: 18, background: C.orange, color: "#fff",
        fontFamily: F.sans, fontWeight: 700, fontSize: 20, display: "flex", alignItems: "center", justifyContent: "center",
      }}>{i + 1}</div>
      {c.zh ? <Translate zh={c.zh} en={c.en} tone={c.tone} /> : <div style={{ fontFamily: F.sans, fontSize: 28, fontWeight: 500, color: C.ink, lineHeight: 1.3, paddingTop: 2 }}>{c.en}</div>}
    </div>
  );
};

const LABELS: Record<string, string> = {
  f_onboard: "Setup", f_walk: "Auto walks", f_board: "Circle board", f_bump: "Bump", f_alert: "Going out",
  f_book: "Voice booking", f_find: "Find", f_shade: "Shade", f_report: "Report", f_voice: "Voice",
};

export const Progress: React.FC<{ current: SceneId }> = ({ current }) => {
  const idx = featureIds.indexOf(current);
  return (
    <div style={{ position: "absolute", left: 150, right: 150, bottom: 50, display: "flex", gap: 10, alignItems: "center" }}>
      {featureIds.map((id, i) => (
        <div key={id} style={{ flex: 1 }}>
          <div style={{ height: 4, borderRadius: 2, background: i < idx ? C.roofC : i === idx ? C.orange : C.line }} />
          <div style={{ fontFamily: F.sans, fontSize: 17, marginTop: 8, color: i === idx ? C.orangeDeep : C.ink2, opacity: i === idx ? 1 : 0.6, fontWeight: i === idx ? 600 : 400 }}>
            {LABELS[id]}
          </div>
        </div>
      ))}
    </div>
  );
};
