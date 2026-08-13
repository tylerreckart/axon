/** Web Audio analyser → { rms, low, mid, high } in 0..1. */

function bandEnergy(bins, from, to) {
  let sum = 0;
  const start = Math.max(0, from);
  const end = Math.min(bins.length, to);
  if (end <= start) return 0;
  for (let i = start; i < end; i++) sum += bins[i];
  return sum / (end - start) / 255;
}

export class AudioPresence {
  constructor() {
    this.ctx = null;
    this.analyser = null;
    this.timeData = null;
    this.freqData = null;
    this.micStream = null;
    this.micSource = null;
    this.playbackSource = null;
    this.muted = true;
  }

  async ensureContext() {
    if (this.ctx) {
      if (this.ctx.state === "suspended") await this.ctx.resume();
      return this.ctx;
    }
    const Ctx = window.AudioContext || window.webkitAudioContext;
    this.ctx = new Ctx();
    this.analyser = this.ctx.createAnalyser();
    this.analyser.fftSize = 1024;
    this.analyser.smoothingTimeConstant = 0.72;
    this.timeData = new Uint8Array(this.analyser.fftSize);
    this.freqData = new Uint8Array(this.analyser.frequencyBinCount);
    if (this.ctx.state === "suspended") await this.ctx.resume();
    return this.ctx;
  }

  async enableMic() {
    await this.ensureContext();
    if (this.micStream) return;
    this.micStream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true },
      video: false,
    });
    this.micSource = this.ctx.createMediaStreamSource(this.micStream);
    this.micSource.connect(this.analyser);
    this.muted = false;
  }

  disableMic() {
    if (this.micSource) {
      try {
        this.micSource.disconnect();
      } catch {
        /* already disconnected */
      }
      this.micSource = null;
    }
    if (this.micStream) {
      for (const track of this.micStream.getTracks()) track.stop();
      this.micStream = null;
    }
    this.muted = true;
  }

  /**
   * Tap an <audio> or AudioNode so speaking TTS drives the shader.
   * @param {HTMLMediaElement|AudioNode} source
   */
  async tapPlayback(source) {
    await this.ensureContext();
    if (this.playbackSource) {
      try {
        this.playbackSource.disconnect();
      } catch {
        /* already disconnected */
      }
      this.playbackSource = null;
    }
    if (source instanceof AudioNode) {
      source.connect(this.analyser);
      this.playbackSource = source;
      return;
    }
    this.playbackSource = this.ctx.createMediaElementSource(source);
    this.playbackSource.connect(this.analyser);
    this.playbackSource.connect(this.ctx.destination);
  }

  sample() {
    if (!this.analyser) {
      return { rms: 0, low: 0, mid: 0, high: 0 };
    }
    this.analyser.getByteTimeDomainData(this.timeData);
    this.analyser.getByteFrequencyData(this.freqData);

    let acc = 0;
    for (let i = 0; i < this.timeData.length; i++) {
      const v = (this.timeData[i] - 128) / 128;
      acc += v * v;
    }
    const rms = Math.min(1, Math.sqrt(acc / this.timeData.length) * 2.4);

    const n = this.freqData.length;
    const low = bandEnergy(this.freqData, 1, Math.floor(n * 0.08));
    const mid = bandEnergy(this.freqData, Math.floor(n * 0.08), Math.floor(n * 0.35));
    const high = bandEnergy(this.freqData, Math.floor(n * 0.35), Math.floor(n * 0.75));

    return {
      rms,
      low: Math.min(1, low * 1.8),
      mid: Math.min(1, mid * 1.6),
      high: Math.min(1, high * 1.7),
    };
  }
}
