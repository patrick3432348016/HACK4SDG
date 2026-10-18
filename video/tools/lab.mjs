import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";
const serveUrl = await bundle({ entryPoint: path.resolve(process.argv[2] || "src/lab/index.ts") });
const composition = await selectComposition({ serveUrl, id: process.argv[3] || "Lab" });
for (const f of (process.argv[4] || "0,30").split(",").map(Number)) {
  await renderStill({ composition, serveUrl, frame: f, output: `out/lab_${f}.png`, chromiumOptions: { gl: "angle" } });
  console.log("still", f);
}
