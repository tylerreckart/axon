import SwiftUI
import UIKit
import MetalKit

struct ThoughtformView: UIViewRepresentable {
    @ObservedObject var presence: ThoughtformPresence

    func makeCoordinator() -> Coordinator {
        Coordinator(presence: presence)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.delegate = context.coordinator.renderer
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.02, green: 0.008, blue: 0.0, alpha: 1)
        view.backgroundColor = UIColor(red: 0.02, green: 0.008, blue: 0.0, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Coordinator {
        let device: MTLDevice
        let renderer: ThoughtformRenderer

        init(presence: ThoughtformPresence) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let renderer = ThoughtformRenderer(device: device, presence: presence)
            else {
                fatalError("thoughtform: Metal is required")
            }
            self.device = device
            self.renderer = renderer
        }
    }
}

#if os(macOS)
#error("ThoughtformView is UIKit-hosted; wrap MTKView in NSViewRepresentable for Mac.")
#endif
