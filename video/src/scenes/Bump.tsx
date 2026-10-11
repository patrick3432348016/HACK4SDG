import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Progress } from "../components/FeatureScene";
import { ease } from "../components/Iso";
import { Phone, ScreenVideo, SCREEN_RATIO, Seg } from "../components/Phone";
import { Eyebrow, Kinetic, PaperBg, Translate } from "../components/Type";
import { featureIds, scene } from "../timeline";
import { C, F, paperShadow } from "../tokens";

export const BUMP_LEFT: Seg[] = [
  { clip: "main", from: 12.8, to: 13.9, rate: 0.25 },
  { clip: "main", from: 13.9, to: 15.3, rate: 0.6 },
  { clip: "main", from: 18.6, to: 22 },
];
export const BUMP_RIGHT: Seg[] = [{ clip: "bump", from: 6.2, to: 9 }, { clip: "bump", from: 13.6, to: 18 }];

const SW = 330;

export const Bump: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = scene("f_bump");
  const l = s.lines[0];
  const at = (f: number) => l.from + l.dur * f;
  const n = String(featureIds.indexOf("f_bump") + 1).padStart(2, "0");

  const hit = at(0.5); // "Bump phones…"
  const approach = interpolate(frame, [at(0.3), hit], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: (t) => t * t * t });
  const recoil = spring({ frame: frame - hit, fps, config: { damping: 9, stiffness: 160 } });
  const gap = interpolate(approach, [0, 1], [260, 0]) + (frame > hit ? (1 - recoil) * 0 + recoil * 70 : 0);
  const sh = SW / SCREEN_RATIO;
  const cx = 1340;
  const enter = spring({ frame: frame - 4, fps, config: { damping: 18, stiffness: 90 } });
  const card = spring({ frame: frame - (hit + 10), fps, config: { damping: 14 } });
  const strike = (f: number) => ease(frame, at(f), at(f) + 12);

  return (
    <AbsoluteFill>
      <PaperBg />
      <div style={{ position: "absolute", left: 150, top: 150, width: 720 }}>
        <Eyebrow n={n} label="Bump to connect" at={6} />
        <div style={{ height: 26 }} />
        <Kinetic text="Friends are made / *in person.*" at={12} size={76} />
        <div style={{ display: "flex", gap: 18, marginTop: 50 }}>
          {[["Search friends", 0.04], ["Invite link", 0.12]].map(([t, f], i) => (
            <div key={i} style={{ position: "relative", fontFamily: F.sans, fontSize: 30, color: C.ink2, background: "#fff", borderRadius: 40, padding: "12px 26px", boxShadow: paperShadow, opacity: ease(frame, at(f as number) - 10, at(f as number)) }}>
              {t}
              <div style={{ position: "absolute", left: 16, right: 16, top: "50%", height: 4, background: C.orange, borderRadius: 2, transform: `scaleX(${strike((f as number) + 0.08)})`, transformOrigin: "left" }} />
            </div>
          ))}
        </div>
      </div>

      {/* two phones */}
      <AbsoluteFill style={{ opacity: enter, transform: `translateY(${(1 - enter) * 120}px)` }}>
        {/* UWB ripple */}
        {frame > hit &&
          [0, 1, 2].map((k) => {
            const t = ((frame - hit - k * 9) / 40);
            if (t < 0 || t > 1) return null;
            return <div key={k} style={{ position: "absolute", left: cx - 300 * t, top: 540 - 300 * t, width: 600 * t, height: 600 * t, borderRadius: "50%", border: `4px solid ${C.green}`, opacity: 1 - t }} />;
          })}
        <Phone width={SW} style={{ left: cx - gap / 2 - SW - 12, top: (1080 - sh) / 2 - 12, transform: `rotate(${-6 * (1 - approach) + 2}deg)` }}>
          <ScreenVideo segs={BUMP_LEFT} frames={s.dur} width={SW} />
        </Phone>
        <Phone width={SW} style={{ left: cx + gap / 2 - 12, top: (1080 - sh) / 2 - 12, transform: `rotate(${6 * (1 - approach) - 2}deg)` }}>
          <ScreenVideo segs={BUMP_RIGHT} frames={s.dur} width={SW} />
        </Phone>
      </AbsoluteFill>

      {/* result card */}
      <div style={{
        position: "absolute", left: 150, top: 620, width: 620, background: C.greenTint, borderRadius: 22, boxShadow: paperShadow,
        padding: "24px 30px", opacity: Math.min(1, card * 1.4), transform: `translateY(${(1 - card) * 40}px)`,
      }}>
        <Translate zh="你同 8 樓陳太而家係街坊" en="You and Mrs Chan (8/F) are now neighbours" tone="green" />
      </div>
      <div style={{ position: "absolute", left: 150, top: 790, display: "flex", gap: 16, opacity: ease(frame, at(0.72), at(0.8)) }}>
        {["Ultra-wideband · under 2 s", "QR code for older phones"].map((t) => (
          <div key={t} style={{ fontFamily: F.sans, fontSize: 24, color: C.greenInk, background: "#fff", border: `2px solid ${C.green}`, borderRadius: 30, padding: "8px 20px" }}>{t}</div>
        ))}
      </div>
      <Progress current="f_bump" />
    </AbsoluteFill>
  );
};
