import SwiftUI
import UIKit
import MetalKit

struct AxonView: UIViewRepresentable {
    @ObservedObject var presence: AxonPresence

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
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.backgroundColor = UIColor.black
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Coordinator {
        let device: MTLDevice
        let renderer: AxonRenderer

        init(presence: AxonPresence) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let renderer = AxonRenderer(device: device, presence: presence)
            else {
                fatalError("axon: Metal is required")
            }
            self.device = device
            self.renderer = renderer
        }
    }
}

#if os(macOS)
#error("AxonView is UIKit-hosted; wrap MTKView in NSViewRepresentable for Mac.")
#endif
