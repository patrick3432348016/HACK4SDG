import React from "react";
import { AbsoluteFill } from "remotion";
import type { TransitionPresentation, TransitionPresentationComponentProps } from "@remotion/transitions";
import { C } from "../tokens";

// A sheet of paper sweeping across: the new scene slides in on a slanted edge with a peach band.
type P = Record<string, never>;
const Sweep: React.FC<TransitionPresentationComponentProps<P>> = ({ children, presentationDirection, presentationProgress: p }) => {
  if (presentationDirection === "exiting") {
    return <AbsoluteFill style={{ transform: `scale(${1 - 0.05 * p}) translateX(${-120 * p}px)`, filter: `brightness(${1 - 0.08 * p})` }}>{children}</AbsoluteFill>;
  }
  const e = 1 - Math.pow(1 - p, 3);
  const x = (1 - e) * 2400 - 240; // left edge of the incoming sheet at mid-height
  const slant = 240;
  const clip = `polygon(${x + slant}px 0, 2200px 0, 2200px 1080px, ${x - slant}px 1080px)`;
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ clipPath: clip, boxShadow: "0 0 80px rgba(0,0,0,0.2)" }}>{children}</AbsoluteFill>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
        <polygon points={`${x + slant - 26},0 ${x + slant},0 ${x - slant},1080 ${x - slant - 26},1080`} fill={C.roofC} opacity={p < 1 ? 1 : 0} />
        <polygon points={`${x + slant - 34},0 ${x + slant - 26},0 ${x - slant - 26},1080 ${x - slant - 34},1080`} fill={C.orange} opacity={p < 1 ? 0.9 : 0} />
      </svg>
    </AbsoluteFill>
  );
};
export const paperSweep = (): TransitionPresentation<P> => ({ component: Sweep, props: {} as P });
