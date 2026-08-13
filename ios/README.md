Add `shaders/axon.metal` plus these Swift files to an iOS target.

```swift
import SwiftUI

@main
struct AlfredFaceApp: App {
    @StateObject private var presence = AxonPresence()

    var body: some Scene {
        WindowGroup {
            AxonView(presence: presence)
                .ignoresSafeArea()
                .onAppear { presence.setMode(.idle) }
        }
    }
}
```

`AxonPresence` is the same state machine as `web/js/presence.js`.
See [docs/embedding.md](../docs/embedding.md).
