/* Capture PCM16 at 16 kHz, in 200 ms packets. No recording persisted. */
class Capture extends AudioWorkletProcessor {
  constructor() {
    super(); this.ratio = sampleRate / 16000; this.remaining = this.ratio;
    this.sum = 0; this.buffer = new Int16Array(3200); this.at = 0;
    this.energy = 0; this.hot = 0; this.silent = 0; this.inSpeech = false;
  }
  process(inputs) {
    const input = inputs[0]?.[0];
    if (!input) return true;
    for (const sample of input) {
      let available = 1;
      while (available > 1e-8) {
        const weight = Math.min(available, this.remaining);
        this.sum += sample * weight; this.remaining -= weight; available -= weight;
        if (this.remaining < 1e-8) {
          const x = Math.max(-1, Math.min(1, this.sum / this.ratio));
          this.buffer[this.at++] = x < 0 ? x * 32768 : x * 32767;
          this.energy += x*x; this.sum = 0; this.remaining = this.ratio;
          if (this.at === this.buffer.length) {
            const rms = Math.sqrt(this.energy / this.at);
            if (rms > .025) { this.hot++; this.silent = 0; } else { this.hot = 0; this.silent++; }
            const onset = !this.inSpeech && this.hot >= 2;
            if (onset) this.inSpeech = true;
            if (this.silent >= 3) this.inSpeech = false;
            this.port.postMessage({pcm: this.buffer.buffer, rms, onset}, [this.buffer.buffer]);
            this.buffer = new Int16Array(3200); this.at = 0; this.energy = 0;
          }
        }
      }
    }
    return true;
  }
}
registerProcessor("voice-capture", Capture);
