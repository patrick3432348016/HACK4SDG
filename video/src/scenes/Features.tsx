import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { FeatureConfig, FeatureScene } from "../components/FeatureScene";
import { ease } from "../components/Iso";
import { scene } from "../timeline";
import { C, F, paperShadow } from "../tokens";

// Seconds below are positions in the recorded clips (see footage/sheets + src/clips.json).
export const FEATURES: Record<string, FeatureConfig> = {
  f_onboard: {
    id: "f_onboard",
    label: "One-minute setup",
    title: "Set up in a minute, / *consent* first.",
    side: "right",
    segs: [
      { clip: "onboarding", from: 10.6, to: 13.5 },
      { clip: "onboarding", from: 15, to: 16.5 },
      { clip: "onboarding", from: 19.5, to: 23.5 },
      { clip: "onboarding", from: 3, to: 5.8 },
    ],
    callouts: [
      { at: 0.04, u: 0.5, v: 0.45, zh: "撳一下你住嗰座樓", en: "Tap your own building on the 3D map" },
      { at: 0.5, u: 0.73, v: 0.47, zh: "長者 · 拐杖", en: "Avatars with a cane, wheelchair or pram", tone: "orange" },
      { at: 0.77, u: 0.4, v: 0.37, zh: "歡迎嚟到街坊行", en: "Who sees what — read aloud before you agree", tone: "green" },
    ],
  },
  f_walk: {
    id: "f_walk",
    label: "Automatic walks",
    title: "Just walk. / It *records itself.*",
    side: "left",
    segs: [
      { clip: "main", from: 31.6, to: 41 },
      { clip: "main", from: 4.6, to: 7.3 },
    ],
    callouts: [
      { at: 0.08, u: 0.3, v: 0.684, zh: "行緊 · 3 分鐘", en: "Walking · 3 min — started on its own", tone: "orange" },
      { at: 0.4, u: 0.5, v: 0.03, en: "Live in the Dynamic Island" },
      { at: 0.8, u: 0.5, v: 0.178, zh: "你屋企 · 已隱身", en: "Home learned from where you sleep — and always hidden" },
    ],
  },
  f_board: {
    id: "f_board",
    label: "Circle board",
    title: "Meet the people / on *your streets.*",
    side: "right",
    segs: [
      { clip: "main", from: 4.6, to: 7.4, rate: 0.8 },
      { clip: "main", from: 7.6, to: 13 },
    ],
    callouts: [
      { at: 0.05, u: 0.5, v: 0.27, en: "Paper-cut model of the streets around home" },
      { at: 0.45, u: 0.86, v: 0.69, zh: "黃太 · 30 日", en: "Ranked by walking streak, in days" },
      { at: 0.72, u: 0.4, v: 0.83, zh: "找人乙 · 你", en: "Strangers see only a nickname and avatar", tone: "orange" },
    ],
  },
  f_alert: {
    id: "f_alert",
    label: "Going-out alerts",
    title: "Know when a / neighbour *heads out.*",
    side: "left",
    segs: [
      { clip: "island_banner", from: 3.8, to: 8.6, rate: 0.7 },
      { clip: "main", from: 26.3, to: 30.5 },
    ],
    callouts: [
      { at: 0.05, u: 0.5, v: 0.1, zh: "8 樓陳太啱啱出門，應該喺皇后山總站嗰邊。", en: "Mrs Chan (8/F) just left — probably by the bus terminus.", tone: "orange" },
      { at: 0.3, u: 0.5, v: 0.03, en: "It grows out of the Dynamic Island" },
      { at: 0.68, u: 0.5, v: 0.1, en: "A landmark, never a map pin" },
    ],
  },
  f_book: {
    id: "f_book",
    label: "Voice booking",
    title: "Say one sentence. / *AI* *does* *the* *rest.*",
    side: "right",
    segs: [{ clip: "main", from: 65.6, to: 80.5 }],
    callouts: [
      { at: 0.04, u: 0.4, v: 0.795, zh: "約陳太聽日下晝 3 點一齊行", en: "“Walk with Mrs Chan tomorrow at 3 pm”", tone: "orange" },
      { at: 0.2, u: 0.45, v: 0.85, zh: "嗰陣有樓遮住、有櫈、兩個都行 2 分鐘左右", en: "AI picks the park: shaded then, has seats, 2 min for both" },
      { at: 0.72, u: 0.5, v: 0.1, zh: "陳太應承咗：聽日下晝 3 點", en: "Read back, confirmed — and Mrs Chan says yes", tone: "green" },
    ],
  },
  f_find: {
    id: "f_find",
    label: "Find each other",
    title: "No map. / Just *follow the arrow.*",
    side: "left",
    segs: [
      { clip: "main", from: 42.5, to: 46, rate: 1.4 },
      { clip: "main", from: 50, to: 59.5 },
    ],
    callouts: [
      { at: 0.24, u: 0.5, v: 0.12, zh: "陳太喺皇后山總站等你 · 大約 1 分鐘到", en: "Mrs Chan is waiting · about 1 min away" },
      { at: 0.42, u: 0.17, v: 0.79, zh: "26 米 · 陳太就喺附近", en: "Within 50 m: it buzzes, a big arrow points the way", tone: "orange" },
      { at: 0.72, u: 0.5, v: 0.5, zh: "見到喇！", en: "Found each other!", tone: "green" },
    ],
  },
  f_shade: {
    id: "f_shade",
    label: "Heat and shade",
    title: "Hot day? / Walk *in the shade.*",
    side: "right",
    segs: [{ clip: "main", from: 83, to: 90.3 }],
    callouts: [
      { at: 0.08, u: 0.5, v: 0.105, zh: "今日好熱，公園欖仔下晝 3 點後有樓遮住，嗰陣先出門啱啱。", en: "Hot today. The park is in building shade after 3 pm — go then.", tone: "amber" },
    ],
    overlay: ({ frame }) => <HeatCard frame={frame} />,
  },
  f_report: {
    id: "f_report",
    label: "Voice of residents",
    title: "Every complaint / *becomes data.*",
    side: "left",
    segs: [
      { clip: "main", from: 90.5, to: 94 },
      { clip: "main", from: 95.6, to: 104 },
    ],
    callouts: [
      { at: 0.05, u: 0.5, v: 0.3, en: "“Too sunny here” — pinned to the nearest landmark" },
      { at: 0.4, u: 0.5, v: 0.73, zh: "皇后山總站 · 好曬 · 23 人反映", en: "Bus terminus: too sunny · 23 residents → add shade or trees", tone: "amber" },
      { at: 0.72, u: 0.5, v: 0.53, en: "Monthly, anonymous, 10+ residents only → social workers and estate management" },
    ],
  },
  f_voice: {
    id: "f_voice",
    label: "Voice first",
    title: "Speak Cantonese / or *Mandarin.*",
    side: "right",
    segs: [
      { clip: "main", from: 26.4, to: 29.2 },
      { clip: "cmn", from: 25.4, to: 28.2 },
      { clip: "script2", from: 21.2, to: 25.5 },
    ],
    callouts: [
      { at: 0.03, u: 0.5, v: 0.1, zh: "8 樓陳太啱啱出門", en: "Cantonese, Traditional Chinese" },
      { at: 0.3, u: 0.5, v: 0.1, zh: "8 楼陈太刚刚出门", en: "Mandarin, Simplified — switch any time", tone: "orange" },
      { at: 0.6, u: 0.4, v: 0.72, zh: "揀一句", en: "Every voice command has a big-button fallback", tone: "green" },
    ],
  },
};

const HeatCard: React.FC<{ frame: number }> = ({ frame }) => {
  const { fps } = useVideoConfig();
  const s = scene("f_shade");
  const at = s.lines[0].from + s.lines[0].dur * 0.45;
  const p = spring({ frame: frame - at, fps, config: { damping: 15 } });
  const sun = ease(frame, at, at + 90);
  if (frame < at - 1) return null;
  // little iso diagram: sun swings across, a building's shadow sweeps over a bench
  const ang = Math.PI * (0.15 + 0.6 * sun);
  const sx = 210 - Math.cos(ang) * 160;
  const sy = 150 - Math.sin(ang) * 110;
  const shadowLen = interpolate(sun, [0, 1], [20, 150]);
  return (
    <div style={{ position: "absolute", left: 150, top: 640, display: "flex", gap: 26, opacity: Math.min(1, p * 1.4), transform: `translateY(${(1 - p) * 30}px)` }}>
      <div style={{ background: "#fff", borderRadius: 20, boxShadow: paperShadow, padding: "18px 26px", width: 250 }}>
        <div style={{ fontFamily: F.serif, fontSize: 64, color: "#BA7517", fontWeight: 500 }}>39.8°C</div>
        <div style={{ fontFamily: F.sans, fontSize: 21, color: C.ink2, lineHeight: 1.35 }}>Sheung Shui, Aug 2026 — the city’s highest reading</div>
      </div>
      <div style={{ background: "#fff", borderRadius: 20, boxShadow: paperShadow, width: 360, height: 200, position: "relative", overflow: "hidden" }}>
        <svg width={360} height={200}>
          <circle cx={sx} cy={sy} r={18} fill={C.amber} />
          <polygon points={`150,150 ${150 + shadowLen},${150 + shadowLen * 0.25} ${150 + shadowLen},${172 + shadowLen * 0.25} 150,172`} fill="rgba(90,80,120,0.16)" />
          <rect x={110} y={80} width={40} height={92} fill={C.roofC} />
          <rect x={150} y={80} width={22} height={92} fill={C.roofB} />
          <rect x={232} y={160} width={46} height={8} rx={3} fill={sun > 0.6 ? C.green : C.ink2} />
          <text x={226} y={192} fontFamily={F.sans} fontSize={15} fill={C.ink2}>bench</text>
        </svg>
        <div style={{ position: "absolute", left: 16, top: 12, fontFamily: F.sans, fontSize: 18, color: C.ink2 }}>
          {sun > 0.6 ? "3 pm · in shade" : "12 pm · full sun"}
        </div>
      </div>
    </div>
  );
};

export const Feature: React.FC<{ id: string }> = ({ id }) => <FeatureScene cfg={FEATURES[id]} />;
export const useNoop = () => useCurrentFrame();
