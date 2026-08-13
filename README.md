# axon

A **presence shader** for [Alfred](https://github.com/tylerreckart/alfred) and
[Arbiter](https://github.com/tylerreckart/arbiter). One visual, driven by a
small uniform block, that listens, thinks, and speaks with the user.

GLSL ES 3.00 (WebGL 2) is the canonical source — it runs in **Safari on iOS**
and every current desktop browser. A Metal port of the same math is the native
iOS path.

```
mic / PTT ──► listen ──► STT ──► think (Arbiter SSE) ──► speak (TTS PCM) ──► idle
                                    │
                              tool_call raises chaos
```

## Modes

| Mode | Alfred moment | Look |
|------|---------------|------|
| `idle` | waiting | Slow breath, dim Gotham teal |
| `listen` | mic open / PTT | Inward ripples, cooler cyan, mic RMS |
| `think` | STT + Arbiter run | Spiral fold, orbiters, tool-call turbulence |
| `speak` | TTS chunks | Outward shockwaves, amber lift, playback RMS |

The shader never talks to the network. Hosts map Alfred’s turn pipeline and
Arbiter’s SSE catalog onto the [presence protocol](docs/protocol.md).

## Quick start

```sh
python3 -m http.server 4173
# open http://127.0.0.1:4173/web/
```

`1–4` switch modes, `m` the microphone, `a` a simulated full turn.
Serve the **repo root** so `shaders/*.glsl` can be fetched. `file://` will not
work.

```sh
npm test   # presence driver + C++ header
```

## Layout

| Path | What |
|------|------|
| `shaders/thoughtform.frag.glsl` | Canonical visual (WebGL 2) |
| `shaders/thoughtform.vert.glsl` | Full-screen triangle |
| `shaders/thoughtform.metal` | iOS / macOS port |
| `web/js/presence.js` | Mode mixer, Alfred + Arbiter mapping |
| `web/js/renderer.js` | WebGL 2 host |
| `ios/` | `MTKView` + Swift presence driver |
| `include/thoughtform.hpp` | C++ frame + Alfred PCM RMS |
| `protocol/presence.schema.json` | JSON shape for WS/SSE |

## Why WebGL 2 + Metal

| Surface | API | Notes |
|---------|-----|-------|
| Browser, including iOS Safari 15+ | WebGL 2 / GLSL ES 3.00 | Same demo as desktop |
| Native iOS | Metal | Drop `thoughtform.metal` into the app target |
| Alfred (C++) | uniforms / JSON | `thoughtform.hpp` — no GPU in-process required |
| WKWebView | the web demo | Fastest share-the-shader path |

WebGPU/WGSL would split the iOS web and native stories; GLSL ES 3.00 is the
overlap. See [embedding](docs/embedding.md).

## Palette

Defaults are Arbiter **Gotham**: void `#0c1014`, teal `#599cab`, pale cyan
`#99d1ce`, speech amber `#edb443`. Override `u_color_*` / `u_bg` per host.

## License

Apache-2.0
