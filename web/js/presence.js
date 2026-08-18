/** axon presence driver — isomorphic (browser + node). */

export const MODES = Object.freeze(["idle", "listen", "think", "speak"]);

const MODE_INDEX = Object.freeze({
  idle: 0,
  listen: 1,
  think: 2,
  speak: 3,
});

/** White on black. Default. */
export const PLATO = Object.freeze({
  colorA: Object.freeze([1.0, 1.0, 1.0]), // #ffffff
  colorB: Object.freeze([1.0, 1.0, 1.0]), // #ffffff
  colorC: Object.freeze([1.0, 1.0, 1.0]), // #ffffff
  background: Object.freeze([0.0, 0.0, 0.0]), // #000000
});

/** Arbiter Gotham — optional override. */
export const GOTHAM = Object.freeze({
  colorA: Object.freeze([0.349, 0.612, 0.671]), // #599cab
  colorB: Object.freeze([0.6, 0.82, 0.808]), // #99d1ce
  colorC: Object.freeze([0.929, 0.706, 0.263]), // #edb443
  background: Object.freeze([0.047, 0.063, 0.078]), // #0c1014
});

const ARBITER_EFFECTS = Object.freeze({
  request_received: { progress: 0.05, chaosAdd: 0.08, chaosFloor: 0.15 },
  intent: { progress: 0.12, chaosAdd: 0.05, chaosFloor: 0.2 },
  stream_start: { progress: 0.18, chaosAdd: 0.04, chaosFloor: 0.3 },
  agent_start: { progress: 0.22, chaosAdd: 0.06, chaosFloor: 0.35 },
  text: { progressAdd: 0.03, chaosAdd: 0.02, chaosFloor: 0.2 },
  tool_call: { progressAdd: 0.04, chaosPulse: 0.85, chaosFloor: 0.45 },
  file: { progressAdd: 0.03, chaosPulse: 0.7 },
  sub_agent_response: { progressAdd: 0.05, chaosAdd: 0.08, chaosFloor: 0.4 },
  token_usage: { progressAdd: 0.01 },
  advisor: { chaosPulse: 0.75, chaosFloor: 0.4 },
  escalation: { chaosPulse: 0.95, chaosFloor: 0.55 },
  stream_end: { progress: 0.85, chaosAdd: -0.1 },
  error: { chaosPulse: 0.9, chaosFloor: 0.5 },
  done: { progress: 1, chaosAdd: -0.35 },
});

const ALFRED_PHASE_MODE = Object.freeze({
  idle: "idle",
  recording: "listen",
  stt: "think",
  thinking: "think",
  speaking: "speak",
  done: "idle",
  cancelled: "listen",
});

function clamp01(x) {
  return Math.min(1, Math.max(0, Number.isFinite(x) ? x : 0));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function expSmooth(current, target, dt, tau) {
  if (tau <= 0) return target;
  const k = 1 - Math.exp(-Math.max(dt, 0) / tau);
  return lerp(current, target, k);
}

export function modeWeights(mode) {
  const w = [0, 0, 0, 0];
  const i = MODE_INDEX[mode];
  if (i !== undefined) w[i] = 1;
  else w[0] = 1;
  return w;
}

export function defaultBands(amplitude) {
  const a = clamp01(amplitude);
  return [a, a * 0.6, a * 0.3];
}

function hash11(n) {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

/**
 * Simulated speech / listen envelope for demos without a live analyser.
 * `kind` is "listen" (softer, irregular) or "speak" (phrases, pauses, syllables).
 */
export function simulatedEnvelope(time, kind) {
  const t = Math.max(0, time);
  if (kind === "listen") {
    const a =
      0.22 +
      0.18 * Math.sin(t * 2.1) +
      0.12 * Math.sin(t * 5.3 + 0.4) +
      0.08 * Math.max(0, Math.sin(t * 9.0));
    return {
      rms: clamp01(a),
      low: clamp01(a * 0.7),
      mid: clamp01(a * 0.5 + 0.1 * Math.sin(t * 3.2)),
      high: clamp01(0.08 + 0.2 * Math.abs(Math.sin(t * 11.0))),
    };
  }

  // Phrase: ~1.7s of speech, ~0.5s rest — commas, not a metronome.
  const phraseT = (t % 2.2) / 2.2;
  const talkEnd = 0.76;
  let phrase = 0;
  if (phraseT < talkEnd) {
    phrase = Math.pow(Math.sin((phraseT / talkEnd) * Math.PI), 0.45);
  }

  const sylRate = 4.15 + 0.35 * Math.sin(t * 0.37);
  const sylPos = t * sylRate;
  const sylId = Math.floor(sylPos);
  const f = sylPos - sylId;
  const h = hash11(sylId + 2.7);
  const h2 = hash11(sylId + 9.1);

  const attack = 0.1 + 0.08 * h;
  const hold = attack + 0.16 + 0.22 * (1 - h);
  let syllable = 0;
  if (f < attack) syllable = f / Math.max(attack, 1e-4);
  else if (f < hold) syllable = 1;
  else syllable = Math.max(0, 1 - (f - hold) / Math.max(1 - hold, 1e-4));
  syllable = syllable * syllable * (3 - 2 * syllable);
  if (h < 0.16) syllable *= 0.22;
  else if (h > 0.82) syllable = Math.min(1, syllable * 1.18);

  const onset = Math.max(0, 1 - f / Math.max(attack * 1.8, 0.08));
  const cons = phrase * syllable * onset * (0.35 + 0.65 * h2);
  const voiced = phrase * syllable;
  const rms = clamp01(0.03 + 0.9 * voiced + 0.08 * cons);

  return {
    rms,
    low: clamp01(voiced * (0.62 + 0.32 * h)),
    mid: clamp01(voiced * (0.48 + 0.28 * (1 - h)) + cons * 0.12),
    high: clamp01(0.03 + voiced * 0.18 + cons * 0.72),
  };
}

export class PresenceDriver {
  /**
   * @param {object} [opts]
   * @param {number} [opts.modeTau=0.34] seconds to crossfade modes
   * @param {number} [opts.audioTau=0.16] listen / idle audio follow
   * @param {number} [opts.audioAttackTau=0.038] speak onset follow
   * @param {number} [opts.audioReleaseTau=0.095] speak decay follow
   * @param {number} [opts.chaosTau=0.45]
   * @param {number} [opts.quality=1]
   * @param {typeof PLATO} [opts.palette]
   */
  constructor(opts = {}) {
    this.modeTau = opts.modeTau ?? 0.34;
    this.audioTau = opts.audioTau ?? 0.16;
    this.audioAttackTau = opts.audioAttackTau ?? 0.038;
    this.audioReleaseTau = opts.audioReleaseTau ?? 0.095;
    this.chaosTau = opts.chaosTau ?? 0.45;
    this.progressTau = opts.progressTau ?? 0.35;
    this.attentionTau = opts.attentionTau ?? 0.28;
    this.quality = clamp01(opts.quality ?? 1);
    this.palette = opts.palette ?? PLATO;

    this.targetMode = "idle";
    this.weights = [1, 0, 0, 0];
    this.amplitude = 0;
    this.bands = [0, 0, 0];
    this.progress = 0;
    this.attention = 0.15;
    this.chaos = 0;
    this.time = 0;
    this.turnId = null;
    this.transcript = "";
    this.lastArbiterEvent = null;

    this._targetAmp = 0;
    this._targetBands = [0, 0, 0];
    this._targetProgress = 0;
    this._targetAttention = 0.15;
    this._targetChaos = 0;
    this._chaosPulse = 0;
  }

  setMode(mode) {
    if (!MODES.includes(mode)) {
      throw new Error(`unknown axon mode: ${mode}`);
    }
    this.targetMode = mode;
    if (mode === "idle") {
      this._targetProgress = 0;
      this._targetChaos = Math.min(this._targetChaos, 0.12);
      this._targetAttention = 0.15;
    } else if (mode === "listen") {
      this._targetAttention = 0.85;
      this._targetProgress = 0;
    } else if (mode === "think") {
      this._targetAttention = 0.55;
      this._targetProgress = Math.max(this._targetProgress, 0.08);
      this._targetChaos = Math.max(this._targetChaos, 0.28);
    } else if (mode === "speak") {
      this._targetAttention = 0.7;
      this._targetProgress = Math.max(this._targetProgress, 0.35);
      this._targetChaos = Math.min(this._targetChaos, 0.25);
    }
  }

  setAudio({ rms = 0, low, mid, high } = {}) {
    this._targetAmp = clamp01(rms);
    const fallback = defaultBands(this._targetAmp);
    this._targetBands = [
      clamp01(low ?? fallback[0]),
      clamp01(mid ?? fallback[1]),
      clamp01(high ?? fallback[2]),
    ];
  }

  /**
   * Map an Alfred client-side turn phase onto mode + optional metadata.
   * @param {{ phase: string, turnId?: string, transcript?: string }} turn
   */
  ingestAlfredTurn(turn) {
    const phase = turn.phase;
    const mode = ALFRED_PHASE_MODE[phase];
    if (!mode) {
      throw new Error(`unknown Alfred phase: ${phase}`);
    }
    if (turn.turnId) this.turnId = turn.turnId;
    if (typeof turn.transcript === "string") this.transcript = turn.transcript;
    this.setMode(mode);
    if (phase === "thinking" || phase === "stt") {
      this._targetChaos = Math.max(this._targetChaos, 0.3);
    }
    if (phase === "done") {
      this._targetProgress = 0;
      this._chaosPulse = 0;
    }
    return mode;
  }

  /**
   * Fold a native Arbiter SSE event name into chaos/progress.
   * @param {string|{event?: string, type?: string}} event
   */
  ingestArbiterEvent(event) {
    const name =
      typeof event === "string" ? event : event.event || event.type || "";
    const fx = ARBITER_EFFECTS[name];
    this.lastArbiterEvent = name || null;
    if (!fx) return false;
    if (fx.progress != null) this._targetProgress = Math.max(this._targetProgress, fx.progress);
    if (fx.progressAdd) this._targetProgress = clamp01(this._targetProgress + fx.progressAdd);
    if (fx.chaosFloor) this._targetChaos = Math.max(this._targetChaos, fx.chaosFloor);
    if (fx.chaosAdd) this._targetChaos = clamp01(this._targetChaos + fx.chaosAdd);
    if (fx.chaosPulse) this._chaosPulse = Math.max(this._chaosPulse, fx.chaosPulse);
    if (name === "done") this._targetChaos = clamp01(this._targetChaos * 0.4);
    return true;
  }

  /**
   * Advance clocks and return a GPU uniform frame.
   * @param {number} dt seconds
   */
  tick(dt) {
    const step = Number.isFinite(dt) ? Math.min(Math.max(dt, 0), 0.1) : 0;
    this.time += step;

    const targetW = modeWeights(this.targetMode);
    for (let i = 0; i < 4; i++) {
      this.weights[i] = expSmooth(this.weights[i], targetW[i], step, this.modeTau);
    }
    const sum = this.weights[0] + this.weights[1] + this.weights[2] + this.weights[3] || 1;
    for (let i = 0; i < 4; i++) this.weights[i] /= sum;

    const rising = this._targetAmp > this.amplitude;
    const audioTau =
      this.targetMode === "speak"
        ? rising
          ? this.audioAttackTau
          : this.audioReleaseTau
        : this.audioTau;
    this.amplitude = expSmooth(this.amplitude, this._targetAmp, step, audioTau);
    for (let i = 0; i < 3; i++) {
      this.bands[i] = expSmooth(this.bands[i], this._targetBands[i], step, audioTau);
    }

    this._chaosPulse = expSmooth(this._chaosPulse, 0, step, 0.28);
    const chaosTarget = clamp01(Math.max(this._targetChaos, this._chaosPulse));
    this.chaos = expSmooth(this.chaos, chaosTarget, step, this.chaosTau);
    this.progress = expSmooth(this.progress, this._targetProgress, step, this.progressTau);
    this.attention = expSmooth(this.attention, this._targetAttention, step, this.attentionTau);

    if (this.targetMode === "think") {
      this._targetChaos = expSmooth(this._targetChaos, 0.22, step, 2.8);
    } else if (this.targetMode === "idle") {
      this._targetChaos = expSmooth(this._targetChaos, 0, step, 1.2);
      this._targetAmp = expSmooth(this._targetAmp, 0, step, 0.4);
    }

    return this.frame();
  }

  frame() {
    return {
      v: 1,
      mode: this.targetMode,
      time: this.time,
      weights: this.weights.slice(),
      amplitude: this.amplitude,
      bands: this.bands.slice(),
      progress: this.progress,
      attention: this.attention,
      chaos: this.chaos,
      quality: this.quality,
      colorA: this.palette.colorA.slice(),
      colorB: this.palette.colorB.slice(),
      colorC: this.palette.colorC.slice(),
      background: this.palette.background.slice(),
      turnId: this.turnId,
      transcript: this.transcript,
      arbiterEvent: this.lastArbiterEvent,
    };
  }

  toJSON() {
    const f = this.frame();
    return {
      v: 1,
      mode: f.mode,
      amplitude: round4(f.amplitude),
      bands: f.bands.map(round4),
      progress: round4(f.progress),
      attention: round4(f.attention),
      chaos: round4(f.chaos),
      turn_id: f.turnId || undefined,
      transcript: f.transcript || undefined,
      arbiter_event: f.arbiterEvent || undefined,
    };
  }
}

function round4(x) {
  return Math.round(x * 10000) / 10000;
}
