import React from "react";
import { AbsoluteFill, Audio, interpolate, Sequence, staticFile } from "remotion";
import { linearTiming, TransitionSeries } from "@remotion/transitions";
import { paperSweep } from "./components/Transitions";
import { Bump } from "./scenes/Bump";
import { Close, Privacy, Real } from "./scenes/Ending";
import { Feature } from "./scenes/Features";
import { Hook, Insight, Problem } from "./scenes/Opening";
import { timeline, totalFrames, TRANSITION } from "./timeline";
import { C } from "./tokens";

export const HAS_MUSIC = true;

const render = (id: string) => {
  switch (id) {
    case "hook": return <Hook />;
    case "problem": return <Problem />;
    case "insight": return <Insight />;
    case "f_bump": return <Bump />;
    case "privacy": return <Privacy />;
    case "real": return <Real />;
    case "close": return <Close />;
    default: return <Feature id={id} />;
  }
};

export const Pitch: React.FC = () => (
  <AbsoluteFill style={{ background: C.paper }}>
    <TransitionSeries>
      {timeline.flatMap((s, i) => {
        const items = [
          <TransitionSeries.Sequence key={s.id} durationInFrames={s.dur}>{render(s.id)}</TransitionSeries.Sequence>,
        ];
        if (i < timeline.length - 1) {
          items.push(
            <TransitionSeries.Transition key={s.id + "-t"} presentation={paperSweep()} timing={linearTiming({ durationInFrames: TRANSITION })} />,
          );
        }
        return items;
      })}
    </TransitionSeries>
    {timeline.flatMap((s) =>
      s.lines.map((l) => (
        <Sequence key={l.id} from={s.start + l.from} durationInFrames={l.dur + 6}>
          <Audio src={staticFile(`vo/${l.id}.wav`)} />
        </Sequence>
      )),
    )}
    {timeline.slice(0, -1).map((s) => (
      <Sequence key={s.id + "-swish"} from={s.start + s.dur - TRANSITION - 4} durationInFrames={20}>
        <Audio src={staticFile("swish.wav")} volume={0.55} />
      </Sequence>
    ))}
    {HAS_MUSIC && (
      <Audio
        src={staticFile("music.wav")}
        loop
        volume={(f) => {
          const talking = timeline.some((s) => s.lines.some((l) => f >= s.start + l.from - 8 && f <= s.start + l.from + l.dur + 8));
          const fade = interpolate(f, [0, 30, totalFrames - 90, totalFrames], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
          return (talking ? 0.16 : 0.42) * fade;
        }}
      />
    )}
  </AbsoluteFill>
);
