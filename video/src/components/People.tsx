import React from "react";
import { C } from "../tokens";

// Flat paper pictogram people, same family as the walkers in the estate.
export type PersonKind = "adult" | "child" | "elder";

export const Person: React.FC<{ kind?: PersonKind; color?: string; size?: number; style?: React.CSSProperties }> = ({
  kind = "adult", color = C.grey, size = 80, style,
}) => {
  const k = kind === "child" ? 0.72 : 1;
  const h = size * k;
  return (
    <svg width={size * 0.6} height={size} viewBox={`0 0 60 100`} style={{ overflow: "visible", ...style }}>
      <g transform={`translate(30,100) scale(${k}) translate(-30,-100)`}>
        <circle cx={30} cy={kind === "elder" ? 24 : 20} r={13} fill={color} />
        <rect x={15} y={kind === "elder" ? 42 : 38} width={30} height={kind === "elder" ? 54 : 58} rx={15} fill={color} />
        {kind === "elder" && <path d="M50 58 L50 98 M50 58 Q50 52 56 52" stroke={color} strokeWidth={5} strokeLinecap="round" fill="none" />}
      </g>
      <ellipse cx={30} cy={99} rx={18 * k} ry={3} fill="rgba(80,60,40,0.10)" />
      {h < 0 && null}
    </svg>
  );
};
