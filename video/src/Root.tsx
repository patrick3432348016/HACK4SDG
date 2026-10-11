import React from "react";
import { Composition } from "remotion";
import { Pitch } from "./Pitch";
import { totalFrames } from "./timeline";
import { FPS, H, W } from "./tokens";

export const Root: React.FC = () => (
  <Composition id="Pitch" component={Pitch} durationInFrames={totalFrames} fps={FPS} width={W} height={H} />
);
