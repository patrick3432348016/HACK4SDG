import React from "react";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Estate } from "../components/Estate";
import { ease } from "../components/Iso";
import { Card, CountUp, Eyebrow, Kinetic, PaperBg } from "../components/Type";
import { scene } from "../timeline";
import { C, F, paperShadow } from "../tokens";

/* ───────────── Privacy ───────────── */
const scramble = (text: string, t: number, frame: number) =>
  text.split("").map((ch, i) => (/[0-9]/.test(ch) && t > i / text.length ? "0123456789#*"[(frame * 7 + i * 13) % 12] : ch)).join("");

export const Privacy: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const l = scene("privacy").lines[0];
  const at = (f: number) => l.from + l.dur * f;
  const fly = ease(frame, at(0.28), at(0.42));
  const scr = ease(frame, at(0.2), at(0.34));
  const shield = spring({ frame: frame - at(0.62), fps, config: { damping: 14 } });
  return (
    <AbsoluteFill>
      <PaperBg />
      <div style={{ position: "absolute", left: 150, top: 140 }}>
        <Eyebrow label="Privacy by design" at={4} />
        <div style={{ height: 24 }} />
        <Kinetic text="Your exact location / *never leaves your phone.*" at={10} size={80} />
      </div>
      {/* phone side */}
      <Card at={at(0.05)} style={{ left: 150, top: 470, width: 560, padding: "28px 32px" }}>
        <div style={{ fontFamily: F.sans, fontSize: 22, color: C.ink2, letterSpacing: "0.1em" }}>ON YOUR PHONE</div>
        <div style={{ fontFamily: "Menlo, monospace", fontSize: 40, color: C.ink, marginTop: 14, opacity: 1 - scr * 0.55 }}>
          {scramble("22.5044, 114.1563", scr, frame)}
        </div>
        <div style={{ fontFamily: F.sans, fontSize: 22, color: C.ink2, marginTop: 10 }}>raw GPS track · stays here</div>
      </Card>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <path d="M 730 600 C 900 500, 1050 500, 1190 600" fill="none" stroke={C.roofC} strokeWidth={3} strokeDasharray="8 10" opacity={ease(frame, at(0.24), at(0.3))} />
      </svg>
      <Card at={at(0.3)} style={{ left: 1210, top: 470, width: 560, padding: "28px 32px", background: C.orangeTint }}>
        <div style={{ fontFamily: F.sans, fontSize: 22, color: "#993C1D", letterSpacing: "0.1em" }}>ON OUR SERVER</div>
        <div style={{ fontFamily: F.sans, fontSize: 36, color: "#712B13", marginTop: 14, fontWeight: 500, minHeight: 50 }}>
          {" "}
        </div>
        <div style={{ fontFamily: F.sans, fontSize: 22, color: "#993C1D", marginTop: 10 }}>no coordinates · no flat number</div>
      </Card>
      {/* travelling landmark chip */}
      <div style={{
        position: "absolute", top: interpolate(fly, [0, 1], [560, 538]), left: interpolate(fly, [0, 1], [430, 1240]), transform: `translateY(${-Math.sin(fly * Math.PI) * 70}px)`,
        background: C.orange, color: "#fff", borderRadius: 30, padding: "10px 22px", fontFamily: F.sans, fontSize: 26, fontWeight: 500,
        opacity: frame > at(0.26) ? 1 : 0, boxShadow: paperShadow, whiteSpace: "nowrap",
      }}>
        <span style={{ fontFamily: F.zh }}>皇后山總站</span>&nbsp; bus terminus
      </div>
      <div style={{ position: "absolute", left: 150, right: 150, top: 760, display: "flex", gap: 24, opacity: Math.min(1, shield * 1.4), transform: `translateY(${(1 - shield) * 30}px)` }}>
        {[
          ["Strangers", "never see where you are"],
          ["Neighbours", "see a landmark, only while you’re out"],
          ["Your home", "always hidden"],
        ].map(([a, b], i) => (
          <div key={i} style={{ flex: 1, background: "#fff", borderRadius: 20, boxShadow: paperShadow, padding: "22px 28px", display: "flex", gap: 18, alignItems: "center" }}>
            <svg width={44} height={44} viewBox="0 0 24 24"><path d="M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6l7-3z" fill={i === 1 ? C.greenTint : C.orangeTint} stroke={i === 1 ? C.green : C.orange} strokeWidth={1.6} /></svg>
            <div>
              <div style={{ fontFamily: F.sans, fontSize: 28, fontWeight: 600, color: C.ink }}>{a}</div>
              <div style={{ fontFamily: F.sans, fontSize: 23, color: C.ink2 }}>{b}</div>
            </div>
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

/* ───────────── It's real ───────────── */
export const Real: React.FC = () => {
  const frame = useCurrentFrame();
  const l = scene("real").lines[0];
  const at = (f: number) => l.from + l.dur * f;
  const tiles: { big: React.ReactNode; label: string; sub: string; f: number }[] = [
    { big: "Live", label: "Shared backend", sub: "Supabase · anonymous sign-in · row-level security", f: 0.28 },
    { big: "GPS", label: "Real location", sub: "Learns home overnight · background walk detection", f: 0.45 },
    { big: "UWB", label: "Ultra-wideband bump", sub: "Nearby Interaction · QR fallback", f: 0.6 },
    { big: <CountUp to={207} at={at(0.72)} dur={36} />, label: "Automated tests", sub: "Plus 35 server permission tests", f: 0.72 },
  ];
  return (
    <AbsoluteFill>
      <PaperBg />
      <div style={{ position: "absolute", left: 150, top: 160 }}>
        <Eyebrow label="Built for real" at={4} />
        <div style={{ height: 24 }} />
        <Kinetic text="This isn’t a *mock-up.*" at={l.from} size={96} />
      </div>
      <div style={{ position: "absolute", left: 150, right: 150, top: 480, display: "flex", gap: 26 }}>
        {tiles.map((t, i) => (
          <Card key={i} at={at(t.f)} style={{ position: "relative", flex: 1, padding: "30px 30px 34px", minHeight: 300 }}>
            <div style={{ fontFamily: F.serif, fontSize: 92, color: C.orange, fontWeight: 500, lineHeight: 1 }}>{t.big}</div>
            <div style={{ fontFamily: F.sans, fontSize: 32, fontWeight: 600, color: C.ink, marginTop: 26 }}>{t.label}</div>
            <div style={{ fontFamily: F.sans, fontSize: 22, color: C.ink2, marginTop: 10, lineHeight: 1.4 }}>{t.sub}</div>
          </Card>
        ))}
      </div>
      <div style={{ position: "absolute", left: 150, bottom: 90, fontFamily: F.sans, fontSize: 24, color: C.ink2, opacity: ease(frame, at(0.85), at(0.95)) }}>
        SwiftUI · SceneKit · Core Motion · Nearby Interaction · Live Activities · on-device speech
      </div>
    </AbsoluteFill>
  );
};

/* ───────────── Close ───────────── */
export const Close: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = scene("close");
  const [l1, l2] = s.lines;
  const zoom = interpolate(frame, [0, s.dur], [1.15, 0.9]);
  const sdg = spring({ frame: frame - l1.from - 30, fps, config: { damping: 14 } });
  const end = spring({ frame: frame - (l2.from + l2.dur + 6), fps, config: { damping: 16 } });
  return (
    <AbsoluteFill>
      <PaperBg />
      <AbsoluteFill style={{ transform: `scale(${zoom})`, opacity: 0.9 - end * 0.82 }}>
        <svg width={1920} height={1080}>
          <g transform="translate(1400,420)">
            <Estate s={26} growAt={-200} pathsAt={-200} walkersAt={-120} walkerCount={8} meet={ease(frame, l2.from, l2.from + 60)} />
          </g>
        </svg>
      </AbsoluteFill>
      <div style={{ position: "absolute", left: 150, top: 220, opacity: 1 - end }}>
        <div style={{ display: "flex", gap: 16, opacity: Math.min(1, sdg * 1.4), transform: `translateY(${(1 - sdg) * 20}px)` }}>
          <span style={{ fontFamily: F.sans, fontSize: 26, fontWeight: 600, padding: "10px 20px", borderRadius: 10, background: "#4C9F38", color: "#fff" }}>SDG 3 · Good health and well-being</span>
          <span style={{ fontFamily: F.sans, fontSize: 26, fontWeight: 600, padding: "10px 20px", borderRadius: 10, background: "#FD9D24", color: "#3a2400" }}>SDG 11 · Sustainable cities</span>
        </div>
        <div style={{ height: 50 }} />
        <Kinetic text="In a new estate, / every walk is a chance / to *meet a neighbour.*" at={l2.from} size={92} stagger={4} />
      </div>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: end }}>
        <div style={{ display: "flex", alignItems: "center", gap: 36, transform: `scale(${0.9 + end * 0.1})` }}>
          <Img src={staticFile("icon.png")} style={{ width: 160, height: 160, borderRadius: 36, boxShadow: paperShadow }} />
          <div>
            <div style={{ display: "flex", alignItems: "baseline", gap: 22 }}>
              <span style={{ fontFamily: F.serif, fontSize: 96, fontWeight: 500, color: C.ink }}>StreetWalk</span>
              <span style={{ fontFamily: F.zh, fontSize: 76, fontWeight: 600, color: C.orange }}>街坊行</span>
            </div>
            <div style={{ fontFamily: F.sans, fontSize: 28, color: C.ink2, marginTop: 8 }}>Hack4SDG 2026 · Track 2 · Team [name]</div>
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
