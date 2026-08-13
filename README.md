# axon

A **presence shader** for [Alfred](https://github.com/tylerreckart/alfred) and
[Arbiter](https://github.com/tylerreckart/arbiter). A small particle blob —
always there, ready — that reads on a phone or a tiny OLED.

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
| `idle` | waiting | Slow-spinning particle blob, quiet breath |
| `listen` | mic open / PTT | Tighter mesh, brighter, more coherent |
| `think` | STT + Arbiter run | Stronger noise, scattered strays |
| `speak` | TTS chunks | Mesh pulses with the voice |

The shader never talks to the network. Hosts map Alfred’s turn pipeline and
Arbiter’s SSE catalog onto the [presence protocol](docs/protocol.md).

## Quick start

```sh
python3 -m http.server 4173
# open http://127.0.0.1:4173/web/
```

The demo loops idle → listen → think → speak. Serve the **repo root** so
`shaders/*.glsl` can be fetched. `file://` will not work.

```sh
npm test   # presence driver + C++ header
```

## Layout

| Path | What |
|------|------|
| `shaders/axon.frag.glsl` | Canonical visual (WebGL 2) |
| `shaders/axon.vert.glsl` | Full-screen triangle |
| `shaders/axon.metal` | iOS / macOS port |
| `web/js/presence.js` | Mode mixer, Alfred + Arbiter mapping |
| `web/js/renderer.js` | WebGL 2 host |
| `ios/` | `MTKView` + Swift presence driver |
| `include/axon.hpp` | C++ frame + Alfred PCM RMS |
| `protocol/presence.schema.json` | JSON shape for WS/SSE |

## Why WebGL 2 + Metal

| Surface | API | Notes |
|---------|-----|-------|
| Browser, including iOS Safari 15+ | WebGL 2 / GLSL ES 3.00 | Same demo as desktop |
| Native iOS | Metal | Drop `axon.metal` into the app target |
| Alfred (C++) | uniforms / JSON | `axon.hpp` — no GPU in-process required |
| WKWebView | the web demo | Fastest share-the-shader path |

WebGPU/WGSL would split the iOS web and native stories; GLSL ES 3.00 is the
overlap. See [embedding](docs/embedding.md).

## Palette

Default palette is **white on black**. Override `u_color_*` / `u_bg` (Arbiter
Gotham is still exported from `presence.js`).

## License

Apache-2.0
