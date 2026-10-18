import React from "react";
import {
  AbsoluteFill, Audio, Easing, Img, interpolate, OffthreadVideo, Sequence, Series, spring, staticFile, useCurrentFrame, useVideoConfig,
} from "remotion";
import { C, F, FPS } from "../tokens";
import { Estate, PATHS } from "../components/Estate";
import { along, iso, IsoPath, Walker } from "../components/Iso";
import { Person, PersonKind } from "../components/People";
import { CountUp, Eyebrow, Kinetic } from "../components/Type";

// StreetWalk 2 分钟英文原型演示（docs/pitch/demo_video_script.md）。
// 素材 public/d2/*：模拟器录屏（30fps，740×1608）、豆包配音、GarageBand 循环配乐。时间一律用秒写，s() 转帧。
// 规矩：每个操作都有手指点击提示；段落之间唔用渐变，用镜头运动 / 手机弹入；碰一碰两部手机一齐出现。

const s = (sec: number) => Math.round(sec * FPS);
const ease = Easing.bezier(0.45, 0, 0.2, 1);
const clamp = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const };
const d2 = (f: string) => staticFile(`d2/${f}`);

// ---------- 配音（秒） ----------
type Line = { id: string; at: number; dur: number; text: string; zh?: string };
const VO: Line[] = [
  { id: "v01", at: 0.8, dur: 7.93, text: "In Hong Kong's Northern Metropolis, seventy thousand new public flats are going up. By 2031, one in four here will be over sixty-five." },
  { id: "v02", at: 9.1, dur: 4.53, text: "One elder, moved here from her village, took three months to find her way home." },
  { id: "v03", at: 14.0, dur: 7.07, text: "Their children commute far. Over half of older people feel lonely, and they want real people, not chatbots." },
  { id: "v04", at: 24.6, dur: 4.02, text: "Pick your block, and StreetWalk rebuilds the two hundred metres around your home." },
  { id: "v05", at: 30.2, dur: 2.41, text: "Step outside, and it starts recording." },
  { id: "v06", at: 33.4, dur: 3.72, text: "It knows which spots are shady right now, and where to sit." },
  { id: "v07", at: 39.2, dur: 5.27, text: "The ranking shows who walks nearby, by nickname only, and how many days in a row." },
  { id: "v08", at: 45.0, dur: 4.29, text: "When they meet, they hold their phones side by side. Neighbours are only made in person." },
  { id: "v09", at: 51.8, dur: 2.89, text: "Neighbours can choose to know when the other goes out." },
  { id: "lee", at: 56.4, dur: 3.7, text: "“Tomorrow at three, ask Mrs Chan for a walk in the park.”", zh: "聽日三點，約陳太去公園行吓。" },
  { id: "v10", at: 61.2, dur: 8.92, text: "One sentence is enough. A language model understands it, and the app picks a spot with shade and seats. Nothing is sent until he says OK." },
  { id: "v11", at: 71.0, dur: 2.76, text: "Mrs Chan taps OK, and it's set for both." },
  { id: "v12", at: 76.6, dur: 1.61, text: "Half an hour before, they get a reminder." },
  { id: "v13", at: 80.0, dur: 7.58, text: "If they can't spot each other, an arrow points the way, and ultra-wideband guides the last few metres. Location is shared only while they look for each other." },
  { id: "v14", at: 93.0, dur: 9.44, text: "On the way, residents can report problems, like too much sun. Issues raised by ten or more people go into an anonymous monthly report for the estate." },
  { id: "v15", at: 103.4, dur: 5.57, text: "Four text sizes, three languages, and a 999 reminder if someone says they've fallen." },
  { id: "v16", at: 110.6, dur: 6.14, text: "Running today on real iPhones, with a real backend. Strangers when they moved in. Neighbours now." },
];
export const DEMO2_SECONDS = 120;

const SEG = {
  hook: [0, 21.6], title: [21.6, 24.4], walk: [24.4, 38.8], tap: [38.8, 51.4], plan: [51.4, 76.2],
  find: [76.2, 92.6], tell: [92.6, 103.0], care: [103.0, 110.2], close: [110.2, 120],
} as const;

// ---------- 录屏 + 手机 + 点击 ----------

/** 一段录屏：src 由 from 秒到 to 秒，speed 倍速。 */
type Cut = { src: string; from: number; to: number; speed?: number };
const cutLen = (c: Cut) => (c.to - c.from) / (c.speed ?? 1);

/** 手指点击：at = 呢部手机自己时间线嘅秒数；x / y = 屏幕比例 */
type TapAt = { at: number; x: number; y: number };

const TapDot: React.FC<TapAt & { w: number; h: number }> = ({ at, x, y, w, h }) => {
  const f = useCurrentFrame();
  const t = (f - s(at)) / FPS;          // 0 = 按落去
  if (t < -0.45 || t > 0.7) return null;
  const appear = interpolate(t, [-0.45, -0.15], [0, 1], clamp);
  const press = t < 0 ? 1 : interpolate(t, [0, 0.12, 0.3], [1, 0.78, 1], clamp);
  const leave = interpolate(t, [0.35, 0.7], [1, 0], clamp);
  const ring = interpolate(t, [0, 0.55], [0, 1], clamp);
  const r = w * 0.075;
  return (
    <div style={{ position: "absolute", left: x * w - r, top: y * h - r, width: r * 2, height: r * 2, pointerEvents: "none" }}>
      {t >= 0 && <div style={{ position: "absolute", inset: -r * ring * 1.4, borderRadius: "50%", border: `3px solid rgba(255,255,255,${0.9 * (1 - ring)})`, boxShadow: `0 0 0 2px rgba(31,30,28,${0.25 * (1 - ring)})` }} />}
      <div style={{ position: "absolute", inset: 0, borderRadius: "50%", background: "rgba(255,255,255,0.55)", border: "2px solid rgba(31,30,28,0.35)", boxShadow: "0 4px 14px rgba(0,0,0,0.25)", transform: `scale(${press})`, opacity: appear * leave }} />
    </div>
  );
};

const PH = 1608 / 740;

const Screen: React.FC<{ cuts: Cut[]; taps?: TapAt[]; w: number }> = ({ cuts, taps = [], w }) => {
  const h = w * PH;
  return (
    <>
      <Series>
        {cuts.map((c, i) => (
          <Series.Sequence key={i} durationInFrames={s(cutLen(c))}>
            <OffthreadVideo src={d2(c.src)} startFrom={s(c.from)} playbackRate={c.speed ?? 1} muted
              style={{ width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }} />
          </Series.Sequence>
        ))}
      </Series>
      {taps.map((t, i) => <TapDot key={i} {...t} w={w} h={h} />)}
    </>
  );
};

const Phone: React.FC<{ w: number; children: React.ReactNode }> = ({ w, children }) => {
  const h = w * PH, bez = w * 0.035, r = w * 0.15;
  return (
    <div style={{
      width: w + bez * 2, height: h + bez * 2, borderRadius: r + bez, background: "#1B1B1D", padding: bez,
      boxShadow: "0 30px 80px rgba(60,40,20,0.22), 0 6px 18px rgba(60,40,20,0.12), inset 0 0 0 2px #3A3A3D",
    }}>
      <div style={{ width: w, height: h, borderRadius: r, overflow: "hidden", position: "relative", background: C.paper }}>{children}</div>
    </div>
  );
};

/** 镜头：关键帧 [秒, scale, x, y]（画面中心为原点） */
type Key = [number, number, number, number];
const useCam = (keys: Key[]) => {
  const f = useCurrentFrame();
  if (keys.length === 1) return { sc: keys[0][1], x: keys[0][2], y: keys[0][3] };
  const t = keys.map((k) => s(k[0]));
  const o = { easing: ease, ...clamp };
  return { sc: interpolate(f, t, keys.map((k) => k[1]), o), x: interpolate(f, t, keys.map((k) => k[2]), o), y: interpolate(f, t, keys.map((k) => k[3]), o) };
};
const Cam: React.FC<{ keys: Key[]; children: React.ReactNode }> = ({ keys, children }) => {
  const { sc, x, y } = useCam(keys);
  return <div style={{ position: "absolute", left: "50%", top: "50%", transform: `translate(-50%,-50%) translate(${x}px,${y}px) scale(${sc})` }}>{children}</div>;
};

/** 手机由下面弹上嚟（代替渐变转场） */
const useRise = (at = 0) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - s(at), fps, config: { damping: 18, stiffness: 120, mass: 0.8 } });
  return (1 - p) * 700;
};

/** 右边一部手机：弹入 + 镜头 */
const PhoneShot: React.FC<{ cuts: Cut[]; taps?: TapAt[]; keys?: Key[]; w?: number; rise?: boolean }> = ({ cuts, taps, keys = [[0, 1, 430, 0]], w = 400, rise = true }) => {
  const dy = useRise();
  return (
    <div style={{ position: "absolute", inset: 0, transform: `translateY(${rise ? dy : 0}px)` }}>
      <Cam keys={keys}><Phone w={w}><Screen cuts={cuts} taps={taps} w={w} /></Phone></Cam>
    </div>
  );
};

// ---------- 文字 ----------

const Side: React.FC<{ n: string; tag: string; title: string; note?: string }> = ({ n, tag, title, note }) => (
  <div style={{ position: "absolute", left: 140, top: 290, width: 800 }}>
    <Eyebrow n={n} label={tag} at={2} />
    <div style={{ height: 30 }} />
    <Kinetic text={title} at={5} size={92} lineHeight={1.04} />
    {note && <Kinetic text={note} at={20} size={34} serif={false} weight={400} color={C.ink2} lineHeight={1.35} stagger={1} style={{ marginTop: 28 }} />}
  </div>
);

const Subs: React.FC = () => {
  const f = useCurrentFrame();
  const line = VO.find((l) => f >= s(l.at) && f < s(l.at + l.dur + 0.25));
  if (!line) return null;
  const p = interpolate(f, [s(line.at), s(line.at) + 5], [0, 1], { extrapolateRight: "clamp" });
  const t = f / FPS;
  const centre = t < SEG.walk[0] || t >= SEG.close[0] || (t >= SEG.tap[0] + 5.8 && t < SEG.tap[1]) || (t >= SEG.plan[0] + 19.2 && t < SEG.plan[1]);
  return (
    <div style={{ position: "absolute", left: centre ? 0 : 140, right: centre ? 0 : undefined, width: centre ? undefined : 820, bottom: centre ? 40 : 90, display: "flex", justifyContent: centre ? "center" : "flex-start", opacity: p }}>
      <div style={{ maxWidth: centre ? 1400 : 820, padding: "12px 24px", borderRadius: 14, background: "rgba(31,30,28,0.8)", color: "#fff", textAlign: centre ? "center" : "left" }}>
        {line.zh && <div style={{ font: `500 34px ${F.zh}`, marginBottom: 4 }}>{line.zh}</div>}
        <div style={{ font: `500 28px/1.32 ${F.sans}` }}>{line.text}</div>
      </div>
    </div>
  );
};

// ---------- 开头 ----------

const ES = 26;   // 屋邨 SVG 一格 26px
const LOST_PATH = PATHS[0];

/** 开头三拍，镜头一直郁：① 楼一栋栋起（规模）② 推近跟住一个长者喺一样嘅楼之间行（迷路）③ 横移去「日间」：打工的人离开，剩低长者 */
const Hook: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const B = 9.0, Cc = 13.6;
  const lf = interpolate(t, [B - 0.4, Cc + 0.6], [0.02, 0.86], clamp);
  const [gx, gy] = along(LOST_PATH, lf);
  const [wx, wy] = iso(gx, gy, 0, ES);
  const zA = interpolate(t, [0, B], [1.28, 1.0], { easing: ease, ...clamp });
  const txA = interpolate(t, [0, B], [1500, 1440], clamp), tyA = interpolate(t, [0, B], [300, 330], clamp);
  const zB = interpolate(t, [B, Cc], [1.0, 1.5], { easing: ease, ...clamp });
  const m = interpolate(t, [B - 0.2, B + 1.2], [0, 1], { easing: ease, ...clamp });
  const z = t < B ? zA : zB;
  const tx = (1 - m) * txA + m * (1420 - z * wx);
  const ty = (1 - m) * tyA + m * (600 - z * wy);
  const pan = interpolate(t, [Cc - 0.3, Cc + 0.6], [0, -1920], { easing: ease, ...clamp });
  const aOut = interpolate(t, [B - 0.5, B], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ background: C.paper, overflow: "hidden" }}>
      <AbsoluteFill style={{ transform: `translateX(${pan}px)` }}>
        <svg width={1920} height={1080} style={{ position: "absolute" }}>
          <g transform={`translate(${tx},${ty}) scale(${z})`}>
            <Estate s={ES} growAt={4} pathsAt={s(B - 1.2)} walkerCount={0} />
            {t > B - 0.5 && <IsoPath path={LOST_PATH} s={ES} progress={lf} color={C.orange} width={0.16} />}
            {t > B - 0.5 && <Walker gx={gx} gy={gy} s={ES} color={C.orange} scale={1.25} bob={f * 0.35} />}
          </g>
        </svg>
        {t < B + 0.1 && (
          <div style={{ position: "absolute", left: 150, top: 230, transform: `translateX(${-aOut * 120}px)`, opacity: 1 - aOut }}>
            <Eyebrow label="Hong Kong · Northern Metropolis" at={6} />
            <div style={{ fontFamily: F.serif, fontWeight: 500, fontSize: 200, color: C.orange, lineHeight: 1, marginTop: 22, letterSpacing: "-0.03em" }}>
              <CountUp to={70000} at={10} dur={60} />
            </div>
            <Kinetic text="new public flats are going up." at={34} size={46} serif={false} weight={500} />
            <div style={{ height: 50 }} />
            <OneInFour at={4.8} />
          </div>
        )}
        {t >= B - 0.1 && (
          <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: 980, background: `linear-gradient(to right, ${C.paper} 78%, rgba(250,250,248,0))`, opacity: m }} />
        )}
        {t >= B - 0.1 && (
          <div style={{ position: "absolute", left: 150, top: 330 }}>
            <Kinetic text="Same towers, / same corridors." at={s(B)} size={100} color={C.ink2} />
            <div style={{ height: 24 }} />
            <Kinetic text="Three months / to find *home.*" at={s(B + 1.6)} size={100} />
          </div>
        )}
      </AbsoluteFill>
      <AbsoluteFill style={{ transform: `translateX(${pan + 1920}px)` }}>
        {t > Cc - 0.4 && <Daytime at={Cc} />}
      </AbsoluteFill>
      <div style={{ position: "absolute", right: 40, bottom: 12, font: `400 18px ${F.sans}`, color: C.ink2 }}>
        Sources: RTHK 2026; Planning Department projections 2023–2031; DAB commuter survey; HKU elderly loneliness study
      </div>
    </AbsoluteFill>
  );
};

/** 四个人，其中一个变橙：2031 年每四个人有一个 65 岁以上 */
const OneInFour: React.FC<{ at: number }> = ({ at }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const turn = interpolate(f, [s(at + 1.4), s(at + 1.8)], [0, 1], clamp);
  return (
    <div style={{ display: "flex", alignItems: "flex-end", gap: 36 }}>
      <div style={{ display: "flex", gap: 14, alignItems: "flex-end" }}>
        {[0, 1, 2, 3].map((i) => {
          const p = spring({ frame: f - s(at) - i * 4, fps, config: { damping: 14, stiffness: 140 } });
          return <div key={i} style={{ transform: `translateY(${(1 - p) * 40}px)`, opacity: p }}>
            <Person kind={i === 3 ? "elder" : "adult"} color={i === 3 && turn > 0.5 ? C.orange : C.grey} size={110} />
          </div>;
        })}
      </div>
      <Kinetic text="*1* *in* *4* over 65 / by 2031" at={s(at + 0.6)} size={60} />
    </div>
  );
};

/** 日间：打工的人一个个行出画面，剩低两个橙色长者，越拉越远 */
const Daytime: React.FC<{ at: number }> = ({ at }) => {
  const f = useCurrentFrame();
  const t = f / FPS;
  const t2 = at + 3.6;
  const people: { k: PersonKind; c: string; leave?: number }[] = [
    { k: "adult", c: C.grey, leave: 0 }, { k: "elder", c: C.orange }, { k: "adult", c: C.grey, leave: 0.25 }, { k: "child", c: C.amber, leave: 0.5 },
    { k: "adult", c: C.grey, leave: 0.75 }, { k: "elder", c: C.orange }, { k: "adult", c: C.grey, leave: 1.0 },
  ];
  const apart = interpolate(t, [t2, t2 + 2.2], [0, 1], { easing: ease, ...clamp });
  return (
    <AbsoluteFill>
      {t < t2 + 0.3 && (
        <div style={{ position: "absolute", left: 150, top: 320 }}>
          <Kinetic text="By day, / the estate *empties.*" at={s(at + 0.3)} size={100} out={s(t2 - 0.2)} />
        </div>
      )}
      {t >= t2 - 0.1 && (
        <div style={{ position: "absolute", left: 150, top: 300, width: 900 }}>
          <Kinetic text="58% of older people feel lonely." at={s(t2)} size={44} serif={false} color={C.ink2} />
          <div style={{ height: 28 }} />
          <Kinetic text="They want *real* *people,* / not chatbots." at={s(t2 + 0.8)} size={100} />
        </div>
      )}
      <div style={{ position: "absolute", left: 1150, right: 0, top: 640, height: 2, background: C.line }} />
      <div style={{ position: "absolute", left: 1180, top: 480, display: "flex", gap: 22, alignItems: "flex-end" }}>
        {people.map((p, i) => {
          const go = p.leave === undefined ? 0 : interpolate(t, [at + 0.9 + p.leave, at + 2.4 + p.leave], [0, 1], { easing: Easing.in(Easing.quad), ...clamp });
          const spread = p.leave === undefined ? (i === 1 ? -1 : 1) * apart * 110 : 0;
          return (
            <div key={i} style={{ transform: `translateX(${go * 900 + spread}px) translateY(${p.leave === undefined ? 0 : -Math.abs(Math.sin(t * 9 + i)) * 6 * go}px)`, opacity: 1 - go }}>
              <Person kind={p.k} color={p.c} size={150} />
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const Title: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f, fps, config: { damping: 13, stiffness: 120 } });
  return (
    <AbsoluteFill style={{ background: C.paper, alignItems: "center", justifyContent: "center" }}>
      <Img src={staticFile("icon.png")} style={{ width: 150, height: 150, borderRadius: 34, boxShadow: "0 16px 40px rgba(60,40,20,0.18)", transform: `scale(${p}) rotate(${(1 - p) * -12}deg)` }} />
      <Kinetic text="StreetWalk" at={6} size={140} style={{ marginTop: 26, letterSpacing: -2 }} />
      <Kinetic text="Every walk, a chance to meet a *neighbour.*" at={16} size={40} serif={false} weight={400} color={C.ink2} stagger={2} style={{ marginTop: 6 }} />
    </AbsoluteFill>
  );
};

// ---------- 功能段 ----------

const Walk: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper }}>
    <Sequence durationInFrames={s(5.8)}>
      <Side n="01" tag="WALK" title="Your block, / *rebuilt.*" note="200 metres around your home, from OpenStreetMap." />
      <PhoneShot cuts={[{ src: "onboard.mp4", from: 11.6, to: 20.6, speed: 1.55 }]}
        taps={[{ at: 4.06, x: 0.5, y: 0.55 }, { at: 5.6, x: 0.5, y: 0.92 }]}
        keys={[[0, 1.0, 430, 0], [1.0, 1.5, 430, 40], [5.2, 1.5, 430, 40], [5.8, 1.3, 430, -120]]} />
    </Sequence>
    <Sequence from={s(5.8)} durationInFrames={s(8.6)}>
      <Side n="01" tag="WALK" title="Step out. / *It* *records.*" note="Shade and seats, worked out from the buildings around you." />
      <PhoneShot rise={false} cuts={[{ src: "walk.mp4", from: 5.6, to: 8.6 }, { src: "walk.mp4", from: 12.6, to: 18.2 }]}
        keys={[[0, 1.3, 430, -120], [0.6, 1.0, 430, 0], [3.0, 1.85, 430, 330], [6.3, 1.85, 430, 330], [7.3, 1.25, 430, -120], [8.6, 1.25, 430, -120]]} />
    </Sequence>
  </AbsoluteFill>
);

/** 碰一碰：两部手机一齐出现，跟住距离一齐靠近；配对一刻两部之间出波纹 */
const BUMP_A: Cut[] = [{ src: "bump_a.mp4", from: 4.3, to: 9.0, speed: 1.15 }, { src: "bump_a.mp4", from: 9.0, to: 10.3 }, { src: "bump_a.mp4", from: 12.9, to: 14.6 }];
const BUMP_B: Cut[] = BUMP_A.map((c) => ({ ...c, src: "bump_b.mp4", from: c.from + 0.25, to: c.to + 0.25 }));
const BumpPair: React.FC = () => {
  const f = useCurrentFrame();
  const t = f / FPS;
  // 录屏：约 1.0 秒开始量距离（110 cm），4.1 秒到 16 cm，4.3 秒开始配对，5.4 秒变返街坊页，5.4 秒后弹出「而家系街坊」卡
  const near = interpolate(t, [0.9, 4.2], [0, 1], { easing: ease, ...clamp });
  const gap = interpolate(near, [0, 1], [540, 190]);
  const tilt = interpolate(near, [0, 1], [-9, -3]);
  const settle = interpolate(t, [5.4, 6.0], [0, 1], { easing: ease, ...clamp });
  const g = gap + settle * 60;
  const pulse = interpolate(t, [4.4, 5.6], [0, 1], clamp);
  const dy = useRise();
  const w = 300;
  const taps: TapAt[] = [{ at: 0.28, x: 0.5, y: 0.3 }, { at: 6.4, x: 0.5, y: 0.835 }];
  return (
    <AbsoluteFill style={{ background: C.paper }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: 56, display: "flex", justifyContent: "center" }}>
        <Eyebrow n="02" label="TAP" at={2} />
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: 100, display: "flex", justifyContent: "center" }}>
        <Kinetic text="Phones side by side. *Now* *neighbours.*" at={5} size={64} />
      </div>
      <div style={{ position: "absolute", inset: 0, transform: `translateY(${dy}px)` }}>
        {pulse > 0 && pulse < 1 && [0, 0.25, 0.5].map((d, i) => {
          const q = interpolate(pulse, [d, d + 0.5], [0, 1], clamp);
          return <div key={i} style={{ position: "absolute", left: 960 - 60 - q * 260, top: 560 - 60 - q * 260, width: 120 + q * 520, height: 120 + q * 520, borderRadius: "50%", border: `4px solid ${i % 2 ? C.green : C.orange}`, opacity: (1 - q) * 0.8 }} />;
        })}
        <div style={{ position: "absolute", left: 960 - g + 170, width: Math.max(0, 2 * g - 340), top: 560, height: 3, background: C.orange, opacity: 1 - pulse }} />
        {[{ cuts: BUMP_A, x: -g, rot: -tilt, label: "UNCLE LEE" }, { cuts: BUMP_B, x: g, rot: tilt, label: "MRS CHAN" }].map((p, i) => (
          <div key={i} style={{ position: "absolute", left: 960 + p.x, top: 590, transform: `translate(-50%,-50%) rotate(${p.rot}deg)` }}>
            <Phone w={w}><Screen cuts={p.cuts} taps={taps} w={w} /></Phone>
            <div style={{ marginTop: 16, textAlign: "center", font: `600 26px ${F.sans}`, color: C.ink2, letterSpacing: 1 }}>{p.label}</div>
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const Tap: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper }}>
    <Sequence durationInFrames={s(5.8)}>
      <Side n="02" tag="TAP" title="Same faces, / *every* *day.*" note="Nicknames only. No address, no map pin." />
      <PhoneShot cuts={[{ src: "board.mp4", from: 4.9, to: 10.4, speed: 0.95 }]} keys={[[0, 1.0, 430, 0], [5.8, 1.12, 430, 60]]} />
    </Sequence>
    <Sequence from={s(5.8)} durationInFrames={s(6.8)}><BumpPair /></Sequence>
  </AbsoluteFill>
);

const Label: React.FC<{ text: string }> = ({ text }) => (
  <div style={{ marginTop: 22, textAlign: "center", font: `600 26px ${F.sans}`, color: C.ink2, letterSpacing: 1 }}>{text}</div>
);

const SplitPlan: React.FC = () => {
  const dy = useRise();
  return (
    <AbsoluteFill style={{ flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 170, transform: `translateY(${dy}px)` }}>
      <div><Phone w={330}><Screen w={330} cuts={[{ src: "voice.mp4", from: 19.0, to: 19.1, speed: 0.1 / 4.5 }, { src: "voice.mp4", from: 20.2, to: 21.4 }]} /></Phone><Label text="UNCLE LEE" /></div>
      <div><Phone w={330}><Screen w={330} cuts={[{ src: "invited.mp4", from: 4.8, to: 9.9, speed: 1.3 }, { src: "invited.mp4", from: 9.9, to: 11.6 }]} taps={[{ at: 3.85, x: 0.5, y: 0.813 }]} /></Phone><Label text="MRS CHAN" /></div>
    </AbsoluteFill>
  );
};

const Plan: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper }}>
    <Sequence durationInFrames={s(4.6)}>
      <Side n="03" tag="PLAN" title="She's out. / *He* *knows.*" note="Out-and-about alerts, by landmark only." />
      <PhoneShot cuts={[{ src: "alert.mp4", from: 4.3, to: 8.9 }]} keys={[[0, 1.0, 430, 0], [0.8, 1.45, 430, 300], [4.6, 1.45, 430, 300]]} />
    </Sequence>
    <Sequence from={s(4.6)} durationInFrames={s(14.6)}>
      <Side n="03" tag="PLAN" title="One sentence. / *A* *plan* *for* *two.*" note="He speaks Cantonese. The app reads it back before anything is sent." />
      <PhoneShot rise={false} cuts={[{ src: "voice.mp4", from: 5.6, to: 20.2 }]} taps={[{ at: 0.3, x: 0.873, y: 0.379 }, { at: 11.3, x: 0.593, y: 0.92 }]}
        keys={[[0, 1.45, 430, 300], [0.6, 1.3, 430, -110], [5.0, 1.3, 430, -110], [5.8, 1.55, 430, -330], [14.6, 1.55, 430, -330]]} />
    </Sequence>
    <Sequence from={s(19.2)} durationInFrames={s(5.6)}><SplitPlan /></Sequence>
  </AbsoluteFill>
);

const Find: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper }}>
    <Side n="04" tag="FIND" title="Follow the arrow. / *Found* *them.*" note="Live location only while they look for each other." />
    <PhoneShot cuts={[{ src: "find.mp4", from: 3.9, to: 7.4 }, { src: "find.mp4", from: 8.4, to: 24, speed: 2.6 }, { src: "find.mp4", from: 24, to: 31.6, speed: 1.1 }]}
      taps={[{ at: 3.0, x: 0.5, y: 0.186 }]}
      keys={[[0, 1.0, 430, 0], [0.6, 1.4, 430, 300], [3.5, 1.4, 430, 300], [4.2, 1.0, 430, 0], [16.4, 1.0, 430, 0]]} />
  </AbsoluteFill>
);

const Tell: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper }}>
    <Sequence durationInFrames={s(4.8)}>
      <Side n="05" tag="TELL" title="“Too sunny / *here.”*" note="Pinned to the nearest landmark." />
      <PhoneShot cuts={[{ src: "report.mp4", from: 6.0, to: 11.4, speed: 1.12 }]} taps={[{ at: 0.45, x: 0.873, y: 0.379 }]}
        keys={[[0, 1.0, 430, 0], [0.9, 1.4, 430, -250], [4.8, 1.4, 430, -250]]} />
    </Sequence>
    <Sequence from={s(4.8)} durationInFrames={s(5.6)}>
      <Side n="05" tag="TELL" title="Many voices, / *one* *report.*" note="Only issues raised by 10+ people. No personal routes." />
      <PhoneShot rise={false} cuts={[{ src: "report.mp4", from: 13.2, to: 18.8 }]} keys={[[0, 1.4, 430, -250], [0.6, 1.0, 430, 0], [5.6, 1.08, 430, 40]]} />
      <div style={{ position: "absolute", right: 70, bottom: 150, font: `500 22px ${F.sans}`, color: C.ink2 }}>Sample data</div>
    </Sequence>
  </AbsoluteFill>
);

const Care: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper }}>
    <Side n="06" tag="CARE" title="Built for / *older* *eyes* *and* *ears.*" note="Large text · 粵語 · 普通话 · English · 999 reminder" />
    <PhoneShot cuts={[{ src: "care.mp4", from: 3.0, to: 5.6 }, { src: "lang.mp4", from: 4.8, to: 7.8, speed: 1.2 }, { src: "care.mp4", from: 13.0, to: 15.2 }]}
      taps={[{ at: 0.3, x: 0.093, y: 0.104 }, { at: 1.4, x: 0.607, y: 0.267 }, { at: 1.9, x: 0.823, y: 0.267 }, { at: 3.27, x: 0.5, y: 0.217 }, { at: 4.52, x: 0.81, y: 0.217 }, { at: 5.25, x: 0.873, y: 0.379 }]}
      keys={[[0, 1.0, 430, 0], [0.25, 1.3, 430, 250], [4.9, 1.3, 430, 250], [5.6, 1.3, 430, -280], [7.2, 1.3, 430, -280]]} />
  </AbsoluteFill>
);

const Close: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const lift = spring({ frame: f - s(6.4), fps, config: { damping: 18, stiffness: 90 } });
  return (
    <AbsoluteFill style={{ background: C.paper }}>
      <div style={{ position: "absolute", inset: 0, transform: `translateY(${-lift * 160}px) scale(${1 - lift * 0.25})` }}>
        <Cam keys={[[0, 1.25, 120, 60], [6.4, 1.0, 120, 20]]}>
          <div style={{ width: 1142, height: 1080, position: "relative" }}>
            <OffthreadVideo src={d2("scene_dusk_crop.mp4")} startFrom={s(5)} muted style={{ width: 1142, height: 1080 }} />
            <div style={{ position: "absolute", inset: 0, background: `linear-gradient(to bottom, ${C.paper} 0%, transparent 8%, transparent 74%, ${C.paper} 90%), linear-gradient(to right, ${C.paper} 0%, transparent 10%, transparent 90%, ${C.paper} 100%)` }} />
          </div>
        </Cam>
      </div>
      {f > s(6.3) && (
        <div style={{ position: "absolute", left: 0, right: 0, top: 640, display: "flex", flexDirection: "column", alignItems: "center" }}>
          <Kinetic text="StreetWalk" at={s(6.4)} size={120} style={{ letterSpacing: -2 }} />
          <Kinetic text="Strangers when they moved in. *Neighbours* *now.*" at={s(6.8)} size={36} serif={false} weight={400} color={C.ink2} stagger={2} />
          <div style={{ display: "flex", gap: 18, marginTop: 30, opacity: interpolate(f, [s(7.4), s(7.9)], [0, 1], clamp) }}>
            {[["SDG 3", "Good health and well-being", C.green], ["SDG 11", "Sustainable cities and communities", C.amber]].map(([a, b, c]) => (
              <div key={a} style={{ padding: "10px 22px", borderRadius: 14, border: `2px solid ${c}`, font: `600 24px ${F.sans}`, color: C.ink }}>
                <span style={{ color: c }}>{a}</span> · {b}
              </div>
            ))}
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};

// ---------- 合成 ----------

const seg = (k: keyof typeof SEG, C2: React.FC) => {
  const [a, b] = SEG[k];
  return <Sequence key={k} from={s(a)} durationInFrames={s(b - a)}><C2 /></Sequence>;
};

export const Demo2: React.FC = () => {
  const music = (fr: number) => {
    const t = fr / FPS;
    if (t < 13.4) return 0.32;
    if (t < 14.4) return interpolate(t, [13.4, 14.4], [0.32, 0.12]);
    if (t < 21.4) return 0.12;
    if (t < 24.4) return interpolate(t, [21.4, 22.2], [0.12, 0.55], { extrapolateRight: "clamp" });
    if (t > 116.8) return 0.5;
    return 0.22;
  };
  return (
    <AbsoluteFill style={{ background: C.paper }}>
      {seg("hook", Hook)}{seg("title", Title)}{seg("walk", Walk)}{seg("tap", Tap)}{seg("plan", Plan)}
      {seg("find", Find)}{seg("tell", Tell)}{seg("care", Care)}{seg("close", Close)}
      <Subs />
      <Audio src={d2("music.wav")} volume={music} />
      {VO.map((l) => (
        <Sequence key={l.id} from={s(l.at)} durationInFrames={s(l.dur + 0.5)}>
          <Audio src={d2(`trim_${l.id}.wav`)} volume={0.95} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};
