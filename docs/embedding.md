# Embedding thoughtform

Same visual on the web, in a WKWebView, or as a native Metal view. The
shader has no I/O; hosts feed it the [presence protocol](protocol.md).

## Web (Safari, Chrome, Firefox, Edge)

WebGL 2 — shipping in **iOS Safari 15+**, so the demo at `web/index.html` is
already the iPhone browser path.

```js
import { PresenceDriver } from "./web/js/presence.js";
import { ThoughtformRenderer, loadShaderSources } from "./web/js/renderer.js";
import { AudioPresence } from "./web/js/audio.js";

const sources = await loadShaderSources(""); // repo root, where /shaders lives
const renderer = new ThoughtformRenderer(canvas, sources);
const driver = new PresenceDriver({ quality: 0.55 }); // phones
const audio = new AudioPresence();

driver.setMode("listen");
await audio.enableMic();

function frame(now) {
  driver.setAudio(audio.sample());
  renderer.resize(1.5);
  renderer.render(driver.tick(dt));
  requestAnimationFrame(frame);
}
```

Serve the **repository root** (so `shaders/thoughtform.frag.glsl` is fetchable):

```sh
python3 -m http.server 4173
# open http://127.0.0.1:4173/web/
```

`file://` will fail shader fetches; use the static server.

## iOS native (Metal)

Add to an Xcode target:

- `shaders/thoughtform.metal` (compiled into the default library)
- `ios/ThoughtformRenderer.swift`
- `ios/ThoughtformView.swift`

```swift
import SwiftUI

struct AlfredFace: View {
    @StateObject private var presence = ThoughtformPresence()

    var body: some View {
        ThoughtformView(presence: presence)
            .ignoresSafeArea()
            .onAppear { presence.setMode(.listen) }
    }
}
```

Drive `ThoughtformPresence` from whatever owns the Alfred HTTP client:

```swift
presence.ingestAlfred(phase: .recording)
presence.setAudio(rms: micRMS, low: l, mid: m, high: h)

// after POST /v1/utterance headers:
presence.ingestAlfred(phase: .thinking, turnId: turnId, transcript: transcript)

// first PCM chunk:
presence.ingestAlfred(phase: .speaking)
```

`MTKView` is the same pattern as [Chroma-Viewer](https://github.com/tylerreckart/Chroma-Viewer)’s `MetalRenderer`.

## iOS via WKWebView

If you do not want a Metal target, load `web/index.html` (from the bundle or a
local server) in a full-screen `WKWebView`. Call into the page with

```js
window.thoughtformSetMode("think")
```

once you expose a small bridge from `demo.js`. Native Metal is the lower-power
path; WKWebView is the fastest way to share one shader with the website.

## Alfred (C++)

Alfred’s pipeline is transport-agnostic (`TurnPipeline` + `AudioSink`). A
future presence emitter can publish `thoughtform::Frame` from the same
moments the HTTP handler already knows about:

| Hook | Frame |
|------|--------|
| Client recording (not in-process today) | `listen` |
| `stt_->transcribe` running | `think`, chaos ~0.3 |
| `arbiter_->send_message` callbacks | `ingestArbiterEvent(...)` |
| first `sink.write` | `speak`, amplitude from PCM RMS |
| `unregister_turn` | `idle` |
| `cancel_turn` | `listen` |

Header: [`include/thoughtform.hpp`](../include/thoughtform.hpp). JSON schema:
[`protocol/presence.schema.json`](../protocol/presence.schema.json).

Until Alfred grows `GET /v1/presence`, keep the driver on the **device or
browser** that holds the mic and the speaker.

## Arbiter SSE

If a host talks to `arbiter --api` directly (no Alfred), parse the native
stream and call `PresenceDriver.ingestArbiterEvent(eventName)` for each
`event:` line. Stay in `think` until you have audio or a finished reply, then
`speak` / `idle`.
