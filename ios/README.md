Add `shaders/thoughtform.metal` plus these Swift files to an iOS target.

```swift
import SwiftUI

@main
struct AlfredFaceApp: App {
    @StateObject private var presence = ThoughtformPresence()

    var body: some Scene {
        WindowGroup {
            ThoughtformView(presence: presence)
                .ignoresSafeArea()
                .onAppear { presence.setMode(.idle) }
        }
    }
}
```

`ThoughtformPresence` is the same state machine as `web/js/presence.js`.
See [docs/embedding.md](../docs/embedding.md).
