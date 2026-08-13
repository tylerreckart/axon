import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  PresenceDriver,
  modeWeights,
  defaultBands,
  simulatedEnvelope,
  GOTHAM,
  PLATO,
} from "../web/js/presence.js";
import { parseSseBuffer } from "../web/js/sse.js";

describe("presence driver", () => {
  it("crossfades idle → listen toward listen weight", () => {
    const d = new PresenceDriver({ modeTau: 0.01 });
    d.setMode("listen");
    for (let i = 0; i < 30; i++) d.tick(0.016);
    const f = d.frame();
    assert.equal(f.mode, "listen");
    assert.ok(f.weights[1] > 0.85, `listen weight ${f.weights[1]}`);
    assert.ok(f.weights[0] < 0.15);
  });

  it("maps Alfred phases onto modes", () => {
    const d = new PresenceDriver();
    assert.equal(d.ingestAlfredTurn({ phase: "recording", turnId: "t1" }), "listen");
    assert.equal(d.turnId, "t1");
    assert.equal(d.ingestAlfredTurn({ phase: "stt" }), "think");
    assert.equal(d.ingestAlfredTurn({ phase: "thinking" }), "think");
    assert.equal(d.ingestAlfredTurn({ phase: "speaking" }), "speak");
    assert.equal(d.ingestAlfredTurn({ phase: "done" }), "idle");
    assert.equal(d.ingestAlfredTurn({ phase: "cancelled" }), "listen");
  });

  it("rejects unknown Alfred phases", () => {
    const d = new PresenceDriver();
    assert.throws(() => d.ingestAlfredTurn({ phase: "dancing" }));
  });

  it("folds Arbiter tool_call into a chaos pulse", () => {
    const d = new PresenceDriver({ chaosTau: 0.01, progressTau: 0.01 });
    d.setMode("think");
    d.ingestArbiterEvent("request_received");
    d.ingestArbiterEvent("tool_call");
    const f = d.tick(0.05);
    assert.ok(f.chaos > 0.5, `chaos ${f.chaos}`);
    assert.ok(f.progress > 0.04, `progress ${f.progress}`);
  });

  it("treats done as progress=1 and decaying chaos", () => {
    const d = new PresenceDriver({ chaosTau: 0.01, progressTau: 0.01 });
    d.setMode("think");
    d.ingestArbiterEvent("tool_call");
    d.tick(0.05);
    d.ingestArbiterEvent("done");
    for (let i = 0; i < 40; i++) d.tick(0.016);
    const f = d.frame();
    assert.ok(f.progress > 0.9);
    assert.ok(f.chaos < 0.45);
  });

  it("serializes a protocol v1 JSON frame", () => {
    const d = new PresenceDriver();
    d.setMode("speak");
    d.setAudio({ rms: 0.4, low: 0.3, mid: 0.2, high: 0.1 });
    d.tick(0);
    const j = d.toJSON();
    assert.equal(j.v, 1);
    assert.equal(j.mode, "speak");
    assert.ok(j.amplitude >= 0 && j.amplitude <= 1);
    assert.equal(j.bands.length, 3);
  });
});

describe("helpers", () => {
  it("builds one-hot mode weights", () => {
    assert.deepEqual(modeWeights("idle"), [1, 0, 0, 0]);
    assert.deepEqual(modeWeights("speak"), [0, 0, 0, 1]);
    assert.deepEqual(modeWeights("nope"), [1, 0, 0, 0]);
  });

  it("fills bands from amplitude", () => {
    assert.deepEqual(defaultBands(1), [1, 0.6, 0.3]);
  });

  it("exports Gotham as an optional palette", () => {
    assert.ok(Math.abs(GOTHAM.colorA[0] - 0.349) < 0.01);
    assert.ok(Math.abs(GOTHAM.colorC[0] - 0.929) < 0.01);
  });

  it("defaults to PLATO plasma", () => {
    const d = new PresenceDriver();
    assert.equal(d.palette, PLATO);
    assert.deepEqual(PLATO.colorA, [1, 1, 1]);
    assert.deepEqual(PLATO.colorC, [1, 0.863, 0.627]);
  });

  it("returns a bounded simulated envelope", () => {
    for (const kind of ["listen", "speak"]) {
      const e = simulatedEnvelope(1.25, kind);
      for (const k of ["rms", "low", "mid", "high"]) {
        assert.ok(e[k] >= 0 && e[k] <= 1, `${kind}.${k}=${e[k]}`);
      }
    }
  });
});

describe("arbiter SSE", () => {
  it("parses native event frames", () => {
    const { frames, rest } = parseSseBuffer(
      "event: request_received\ndata: {\"agent\":\"index\"}\n\nevent: text\ndata: {\"delta\":\"hi\"}\n\npartial"
    );
    assert.equal(frames.length, 2);
    assert.equal(frames[0].event, "request_received");
    assert.equal(frames[1].event, "text");
    assert.equal(rest, "partial");
  });
});
