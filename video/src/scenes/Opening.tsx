import React from "react";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Estate } from "../components/Estate";
import { ease } from "../components/Iso";
import { Person, PersonKind } from "../components/People";
import { Card, CountUp, Eyebrow, Kinetic, PaperBg } from "../components/Type";
import { scene } from "../timeline";
import { C, F, paperShadow } from "../tokens";

const lineAt = (id: Parameters<typeof scene>[0], i: number) => scene(id).lines[i].from;

/* ───────────── 1. Hook ───────────── */
export const Hook: React.FC = () => {
  const frame = useCurrentFrame();
  const l2 = lineAt("hook", 1);
  const swap = ease(frame, l2 - 8, l2 + 6);
  const cam = interpolate(frame, [0, scene("hook").dur], [1.06, 1.0]);
  return (
    <AbsoluteFill>
      <PaperBg />
      <AbsoluteFill style={{ transform: `scale(${cam})` }}>
        <svg width={1920} height={1080} style={{ position: "absolute" }}>
          <g transform="translate(1360,420)">
            <Estate s={28} growAt={14} pathsAt={l2 - 10} walkersAt={l2} walkerCount={5} />
          </g>
        </svg>
      </AbsoluteFill>
      <div style={{ position: "absolute", left: 150, top: 300, opacity: 1 - swap, transform: `translateY(${-swap * 30}px)` }}>
        <Eyebrow label="Hong Kong · Northern Metropolis" at={8} />
        <div style={{ fontFamily: F.serif, fontWeight: 500, fontSize: 230, color: C.orange, lineHeight: 1, marginTop: 24, letterSpacing: "-0.03em" }}>
          <CountUp to={38000} at={10} dur={48} />
        </div>
        <Kinetic text="new residents moving into brand-new / public estates, 2026 – 28" at={30} size={40} serif={false} weight={400} color={C.ink2} lineHeight={1.35} stagger={2} />
      </div>
      <div style={{ position: "absolute", left: 150, top: 340, opacity: swap }}>
        <Kinetic text="New keys." at={l2} size={110} />
        <Kinetic text="*No* *neighbours.*" at={l2 + 40} size={110} />
      </div>
      <div style={{ position: "absolute", left: 150, bottom: 70, fontFamily: F.sans, fontSize: 18, color: C.ink2, opacity: ease(frame, 40, 60) * (1 - swap) }}>
        Fung Ling Court + Ku Chuen Estate · Housing Bureau / RTHK, 2026
      </div>
    </AbsoluteFill>
  );
};

/* ───────────── 2. Problem ───────────── */
const Row: React.FC<{ kinds: { k: PersonKind; c?: string; leave?: number; dim?: number }[]; size?: number }> = ({ kinds, size = 120 }) => {
  const frame = useCurrentFrame();
  return (
    <div style={{ display: "flex", gap: size * 0.18, alignItems: "flex-end" }}>
      {kinds.map((p, i) => {
        const go = p.leave !== undefined ? ease(frame, p.leave, p.leave + 26) : 0;
        return (
          <div key={i} style={{ transform: `translateX(${go * 900}px)`, opacity: (1 - go) * (p.dim ?? 1) }}>
            <Person kind={p.k} color={p.c ?? C.grey} size={size} />
          </div>
        );
      })}
    </div>
  );
};

const Stat: React.FC<{ at: number; out: number; big: string; label: string; children?: React.ReactNode; source: string }> = ({ at, out, big, label, children, source }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - at, fps, config: { damping: 16, stiffness: 110 } });
  const o = interpolate(frame, [out - 8, out + 4], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  if (frame < at - 2 || frame > out + 6) return null;
  return (
    <AbsoluteFill style={{ opacity: o }}>
      <div style={{ position: "absolute", left: 150, top: 250, width: 760, transform: `translateY(${(1 - p) * 50}px)`, opacity: p }}>
        <div style={{ fontFamily: F.serif, fontSize: 200, color: C.orange, lineHeight: 1, letterSpacing: "-0.03em", fontWeight: 500 }}>{big}</div>
        <div style={{ fontFamily: F.sans, fontSize: 42, color: C.ink, lineHeight: 1.3, marginTop: 18, fontWeight: 500 }}>{label}</div>
        <div style={{ fontFamily: F.sans, fontSize: 18, color: C.ink2, marginTop: 26 }}>{source}</div>
      </div>
      <div style={{ position: "absolute", left: 1000, top: 0, bottom: 0, right: 80, display: "flex", alignItems: "center", justifyContent: "center" }}>{children}</div>
    </AbsoluteFill>
  );
};

export const Problem: React.FC = () => {
  const frame = useCurrentFrame();
  const s = scene("problem");
  const [l1, l2, l3, l4] = s.lines;
  return (
    <AbsoluteFill>
      <PaperBg />
      <div style={{ position: "absolute", left: 150, top: 150 }}>
        <Eyebrow label="The problem" at={4} />
      </div>
      <Stat at={l1.from - 6} out={l2.from - 4} big="47%" label="of working residents commute more than an hour each way" source="DAB survey of Northern Metropolis residents, 610 respondents">
        <div>
          <Row size={150} kinds={[
            { k: "adult", leave: l1.from + 50 }, { k: "elder", c: C.orange }, { k: "adult", leave: l1.from + 56 },
            { k: "child", c: C.amber }, { k: "adult", leave: l1.from + 62 }, { k: "elder", c: C.orange }, { k: "adult", leave: l1.from + 68 },
          ]} />
          <div style={{ fontFamily: F.sans, fontSize: 28, color: C.ink2, marginTop: 30, opacity: ease(frame, l1.from + 95, l1.from + 115) }}>
            Daytime: <span style={{ color: C.orange }}>older residents</span> and <span style={{ color: "#BA7517" }}>children</span>
          </div>
        </div>
      </Stat>
      <Stat at={l2.from - 4} out={l3.from - 4} big="1 in 4" label="North District residents aged 65+ by 2031" source="Planning Department projection, 2023–2031">
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 40 }}>
          <Row size={210} kinds={[{ k: "adult" }, { k: "adult" }, { k: "adult" }, { k: "elder", c: C.orange }]} />
          <div style={{ display: "flex", gap: 18 }}>
            {[["1", "district elderly centre"], ["2027", "Kwu Tung station opens"], ["30 min", "between buses on route 77"]].map(([a, b], i) => (
              <Card key={i} at={l2.from + 70 + i * 10} style={{ position: "relative", padding: "20px 24px", width: 250 }}>
                <div style={{ fontFamily: F.serif, fontSize: 46, color: C.orangeDeep, fontWeight: 500 }}>{a}</div>
                <div style={{ fontFamily: F.sans, fontSize: 21, color: C.ink2, lineHeight: 1.3 }}>{b}</div>
              </Card>
            ))}
          </div>
        </div>
      </Stat>
      <Stat at={l3.from - 4} out={l4.from - 4} big="~50%" label="of older people in Hong Kong feel lonely or isolated" source="CUHK 2025 (45%), HKU (58%)">
        <Lonely at={l3.from} />
      </Stat>
      {frame >= l4.from - 6 && (
        <AbsoluteFill>
          <div style={{ position: "absolute", left: 150, top: 330 }}>
            <Kinetic text="Visits can't come every day." at={l4.from} size={84} color={C.ink2} />
            <div style={{ height: 30 }} />
            <Kinetic text="Step counters count *steps,* / not _friends._" at={l4.from + 50} size={96} />
          </div>
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};

const Lonely: React.FC<{ at: number }> = ({ at }) => {
  const frame = useCurrentFrame();
  const apart = ease(frame, at + 20, at + 70);
  return (
    <div style={{ position: "relative", width: 700, height: 420 }}>
      {[0, 1, 2, 3].map((i) => {
        const x = [130, 250, 370, 490][i] + (i - 1.5) * 50 * apart;
        const dim = i % 2 ? 1 - apart * 0.45 : 1;
        return (
          <div key={i} style={{ position: "absolute", left: x, top: 120 + (i % 2) * 30, opacity: dim }}>
            <Person kind={i % 2 ? "elder" : "adult"} color={i % 2 ? C.orange : C.grey} size={180} />
          </div>
        );
      })}
    </div>
  );
};

/* ───────────── 3. Insight + reveal ───────────── */
export const Insight: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = scene("insight");
  const [l1, l2] = s.lines;
  const reveal = l2.from + 40; // icon + title appear after "So we built StreetWalk"
  const meet = ease(frame, l1.from + 70, l2.from + 10);
  const push = ease(frame, reveal - 20, reveal + 30);
  const iconP = spring({ frame: frame - reveal, fps, config: { damping: 13, stiffness: 100 } });
  return (
    <AbsoluteFill>
      <PaperBg />
      <AbsoluteFill style={{ transform: `scale(${1 + push * 0.5}) translateY(${push * 60}px)`, opacity: 1 - push * 0.85, transformOrigin: "960px 560px" }}>
        <svg width={1920} height={1080}>
          <g transform="translate(1320,450)">
            <Estate s={30} growAt={-200} pathsAt={l1.from - 10} walkersAt={l1.from} walkerCount={9} meet={meet} />
          </g>
        </svg>
      </AbsoluteFill>
      <div style={{ position: "absolute", left: 150, top: 150, opacity: 1 - push }}>
        <Kinetic text="People here *already* walk." at={l1.from} size={76} />
        <Kinetic text="Same paths. Same faces." at={l1.from + 45} size={44} serif={false} weight={400} color={C.ink2} style={{ marginTop: 16 }} />
      </div>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: Math.min(1, iconP * 1.5) }}>
        <div style={{ transform: `scale(${0.6 + iconP * 0.4}) translateY(${(1 - iconP) * 40}px)`, display: "flex", flexDirection: "column", alignItems: "center" }}>
          <Img src={staticFile("icon.png")} style={{ width: 230, height: 230, borderRadius: 52, boxShadow: paperShadow }} />
          <div style={{ display: "flex", alignItems: "baseline", gap: 26, marginTop: 44 }}>
            <span style={{ fontFamily: F.serif, fontSize: 120, fontWeight: 500, color: C.ink, letterSpacing: "-0.02em" }}>StreetWalk</span>
            <span style={{ fontFamily: F.zh, fontSize: 96, fontWeight: 600, color: C.orange }}>街坊行</span>
          </div>
        </div>
        <div style={{ marginTop: 24 }}>
          <Kinetic text="Walk. Bump phones. *Become* *neighbours.*" at={reveal + 22} size={46} serif={false} weight={400} color={C.ink2} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
