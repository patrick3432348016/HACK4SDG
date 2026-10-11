// Render review stills: node tools/stills.mjs [scene@fraction ...]  (default: each scene at 0.35 and 0.8)
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";
import fs from "node:fs";

const entry = path.resolve("src/index.ts");
const serveUrl = await bundle({ entryPoint: entry });
const comp = await selectComposition({ serveUrl, id: "Pitch" });
const tl = JSON.parse(process.env.TL);
const want = process.argv.slice(2);
const targets = [];
for (const s of tl) {
  const fr = want.length ? want.filter((w) => w.startsWith(s.id + "@")).map((w) => +w.split("@")[1]) : [0.35, 0.8];
  for (const f of fr) targets.push({ name: `${s.id}_${Math.round(f * 100)}`, frame: Math.min(comp.durationInFrames - 1, s.start + Math.round(s.dur * f)) });
}
fs.mkdirSync("out/stills", { recursive: true });
for (const t of targets) {
  await renderStill({ composition: comp, serveUrl, frame: t.frame, output: `out/stills/${t.name}.jpg`, imageFormat: "jpeg", jpegQuality: 80, scale: 0.5 });
  console.log(t.name, t.frame);
}
console.log("total frames", comp.durationInFrames, (comp.durationInFrames / 30).toFixed(1) + "s");
