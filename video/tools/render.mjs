// Full render with progress log: node tools/render.mjs [out.mp4]
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import path from "node:path";

const out = process.argv[2] || "out/streetwalk_pitch_en.mp4";
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id: process.env.COMP || "Pitch" });
let last = -1;
await renderMedia({
  composition, serveUrl, codec: "h264", crf: 20, audioBitrate: "192k", outputLocation: out, concurrency: 6,
  onProgress: ({ progress, renderedFrames, encodedFrames }) => {
    const p = Math.floor(progress * 100);
    if (p !== last) { last = p; console.log(`${p}% rendered=${renderedFrames} encoded=${encodedFrames}`); }
  },
});
console.log("DONE", out);
