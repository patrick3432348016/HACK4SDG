import vo from "./vo.json";
const FPS = 30; // keep in sync with tokens.ts (no font import here so node tools can read the timeline)

// Narration drives the timeline: every scene lasts as long as its lines plus breathing room.
export type SceneId =
  | "hook" | "problem" | "insight"
  | "f_onboard" | "f_walk" | "f_board" | "f_bump" | "f_alert" | "f_book" | "f_find" | "f_shade" | "f_report" | "f_voice"
  | "privacy" | "real" | "close";

const SCENES: { id: SceneId; lines: string[]; lead?: number; tail?: number }[] = [
  { id: "hook", lines: ["hook1", "hook2"], lead: 40, tail: 24 },
  { id: "problem", lines: ["prob1", "prob2", "prob3", "prob4"] },
  { id: "insight", lines: ["insight1", "insight2"], tail: 50 },
  { id: "f_onboard", lines: ["f_onboard"] },
  { id: "f_walk", lines: ["f_walk"] },
  { id: "f_board", lines: ["f_board"] },
  { id: "f_bump", lines: ["f_bump"], tail: 30 },
  { id: "f_alert", lines: ["f_alert"] },
  { id: "f_book", lines: ["f_book"] },
  { id: "f_find", lines: ["f_find"] },
  { id: "f_shade", lines: ["f_shade"] },
  { id: "f_report", lines: ["f_report"] },
  { id: "f_voice", lines: ["f_voice"] },
  { id: "privacy", lines: ["privacy"], tail: 30 },
  { id: "real", lines: ["real"], tail: 30 },
  { id: "close", lines: ["close1", "close2"], tail: 100 },
];

export const TRANSITION = 18; // frames of overlap between scenes
const GAP = 10; // frames between two lines in one scene
const LEAD = 22; // frames before the first line (>= TRANSITION so the voice starts on a settled frame)
const TAIL = 14;

const sec = (id: string) => (vo as Record<string, number>)[id] ?? 3;
const fr = (s: number) => Math.ceil(s * FPS);

export type LineTiming = { id: string; from: number; dur: number }; // frames, relative to scene start
export type SceneTiming = { id: SceneId; start: number; dur: number; lines: LineTiming[] };

export const timeline: SceneTiming[] = (() => {
  const out: SceneTiming[] = [];
  let cursor = 0;
  for (const s of SCENES) {
    let t = s.lead ?? LEAD;
    const lines: LineTiming[] = [];
    for (const id of s.lines) {
      const d = fr(sec(id));
      lines.push({ id, from: t, dur: d });
      t += d + GAP;
    }
    const dur = t - GAP + (s.tail ?? TAIL);
    out.push({ id: s.id, start: cursor, dur, lines });
    cursor += dur - TRANSITION;
  }
  return out;
})();

export const totalFrames = (() => {
  const last = timeline[timeline.length - 1];
  return last.start + last.dur;
})();

export const scene = (id: SceneId) => timeline.find((s) => s.id === id)!;
export const featureIds = timeline.filter((s) => s.id.startsWith("f_")).map((s) => s.id);
