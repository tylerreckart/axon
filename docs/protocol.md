# Presence protocol

thoughtform is a **presence shader**: one visual, driven by a small uniform
block, that any Alfred / Arbiter host can animate. The shader never talks to
the network. Hosts map voice + SSE onto this frame and upload it every draw.

## Modes

| Mode | When | Motion |
|------|------|--------|
| `idle` | No turn in flight | Sparse plasma blob, slow phosphor breath |
| `listen` | Mic open / PTT held / VAD | Tighter body, inbound dotted ripples |
| `think` | STT done, waiting on Arbiter (and until first TTS chunk) | Edge particles scatter and orbit |
| `speak` | TTS PCM (or model text if you have no audio yet) | Discrete concentric shells, hotter phosphor |

Crossfades happen on the host (`PresenceDriver`). The shader receives a
`vec4 u_weights` (idle, listen, think, speak) that should sum to ~1.

## Uniforms

Packed identically for WebGL 2 (`uniform *`) and Metal (`ThoughtformUniforms`).

| Name | Type | Range | Meaning |
|------|------|-------|---------|
| `u_resolution` | vec2 | px | Drawable size |
| `u_time` | float | seconds | Animation clock |
| `u_weights` | vec4 | 0..1 | Mode mix: idle, listen, think, speak |
| `u_amplitude` | float | 0..1 | RMS of mic (`listen`) or TTS (`speak`) |
| `u_bands` | vec3 | 0..1 | Spectral energy: low, mid, high |
| `u_progress` | float | 0..1 | Position in the current turn |
| `u_attention` | float | 0..1 | How locked-on the presence feels |
| `u_chaos` | float | 0..1 | Thinking turbulence (tool activity) |
| `u_quality` | float | 0..1 | Plasma cell density: 0.5 phone, 1.0 desktop |
| `u_color_a` | vec3 | 0..1 | Plasma orange (`#ff6414`) |
| `u_color_b` | vec3 | 0..1 | Hot phosphor (`#ffb45a`) |
| `u_color_c` | vec3 | 0..1 | Peak (`#ffdca0`) |
| `u_bg` | vec3 | 0..1 | Panel void (`#050200`) |

Canonical JSON for the same frame is [`presence.schema.json`](presence.schema.json).

## Alfred mapping

Alfred today is push-to-talk HTTP: PCM in, chunked PCM out
([docs/api.md](https://github.com/tylerreckart/alfred/blob/main/docs/api.md)).
The **client** that holds the mic/speaker owns presence; Alfred does not yet
emit a presence stream. Drive the shader from the local turn:

| Client moment | Mode | Notes |
|---------------|------|-------|
| Waiting | `idle` | `amplitude → 0` |
| Recording PTT / VAD | `listen` | `amplitude` + `bands` from the mic |
| `POST /v1/utterance` sent, no `X-Transcript` yet | `think` | STT in flight |
| Headers arrived (`X-Turn-Id`, `X-Transcript`), no PCM yet | `think` | Arbiter is reasoning |
| First response PCM byte | `speak` | `amplitude` + `bands` from the TTS stream |
| `sink.done` / body complete | `idle` | |
| `POST /v1/turns/:id/cancel` (barge-in) | `listen` | |

Text path (`POST /v1/utterance/text`) skips STT: jump `idle → think` (or
straight to `speak` on a fast-path reply).

### Proposed Alfred SSE (v1.1)

When Alfred grows duplex WS, emit the same JSON frame:

```
GET /v1/presence          (SSE, device-auth)
event: presence
data: {"v":1,"mode":"think","turn_id":"…","chaos":0.4}
```

Reuse `TurnPipeline` phases: STT start → think, first `AudioSink::write` →
speak, unregister_turn → idle, cancel → listen.

## Arbiter SSE mapping

While `mode === think` (and optionally into `speak`), fold native Arbiter
events ([SSE catalog](https://arbiter.run/docs/concepts/sse-events)) into
`chaos` / `progress`:

| Event | Effect |
|-------|--------|
| `request_received` | `progress = 0.05`, `chaos += 0.08` |
| `intent` | `progress = 0.12`, `chaos += 0.05` |
| `stream_start` / `agent_start` | `progress = 0.2`, `chaos = max(chaos, 0.35)` |
| `tool_call` | pulse `chaos` toward 0.85 (decays in the driver) |
| `text` (depth 0) | raise `progress`; if TTS has not started you may stay in `think` |
| `advisor` / `escalation` | pulse `chaos` |
| `error` | flash `chaos`, keep `think` until the stream ends |
| `done` | `progress = 1`; host switches to `speak` or `idle` |

Alfred already consumes `on_request_id`, master `text` deltas, and `done`
(`ArbiterStreamCallbacks`). A future presence emitter can hook those same
callbacks without a second SSE parser.

## Audio

- **Listen:** Web Audio `AnalyserNode` on `getUserMedia`, or iOS `AVAudioEngine` tap. Feed RMS + 3-band energy.
- **Speak:** same analyser on the TTS playback graph (Web: `MediaElementAudioSource` / `AudioBufferSource`; iOS: tap the player).
- Alfred PCM is **s16le mono 16 kHz**. Band-split with a cheap IIR or FFT (32–64 bins is enough).

If you have no spectrum, set `bands = (amplitude, amplitude * 0.6, amplitude * 0.3)`.

## Palette

Default is **PLATO plasma** (amber cells on `#050200`). Pass Arbiter Gotham
via `u_color_*` / `u_bg` if you want the TUI palette instead.
