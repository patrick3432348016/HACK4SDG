// Synthetic PCM tests for sample rate conversion and packet continuity. No microphone.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../windows/web/capture.js'), 'utf8');
for (const rate of [16000, 44100, 48000]) {
  const packets = []; let Capture;
  const sandbox = {sampleRate: rate, AudioWorkletProcessor: class {constructor(){this.port={postMessage:p=>packets.push(p)};}}, registerProcessor:(name, cls)=>Capture=cls};
  vm.runInNewContext(source, sandbox);
  const worklet = new Capture();
  for(let at=0;at<rate;at+=128) worklet.process([[new Float32Array(Math.min(128,rate-at)).fill(.25)]]);
  assert.equal(packets.length, 5, `one second at ${rate} -> five 200ms packets`);
  for (const packet of packets) {
    assert.equal(packet.pcm.byteLength, 6400);
    assert.equal(new Int16Array(packet.pcm)[0], 8191);
  }
  assert.equal(packets.filter(p=>p.onset).length, 1, 'continuous voice triggers one onset');
}
console.log('PCM tests passed at 16, 44.1 and 48 kHz; no microphone or cloud used.');
