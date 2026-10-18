import React from "react";
import { Composition } from "remotion";
import { Pitch } from "./Pitch";
import { Demo2, DEMO2_SECONDS } from "./demo2/Demo2";
import { totalFrames } from "./timeline";
import { FPS, H, W } from "./tokens";

export const Root: React.FC = () => (
  <>
    <Composition id="Pitch" component={Pitch} durationInFrames={totalFrames} fps={FPS} width={W} height={H} />
    <Composition id="Demo2" component={Demo2} durationInFrames={DEMO2_SECONDS * FPS} fps={FPS} width={W} height={H} />
  </>
);
