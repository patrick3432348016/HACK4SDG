import { timeline } from "../src/timeline";
console.log(JSON.stringify(timeline.map((s) => ({ id: s.id, start: s.start, dur: s.dur }))));
