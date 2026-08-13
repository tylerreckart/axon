import Foundation
import MetalKit
import QuartzCore

final class AxonRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let presence: AxonPresence
    private var lastTime: CFTimeInterval = CACurrentMediaTime()

    init?(device: MTLDevice, presence: AxonPresence) {
        self.device = device
        self.presence = presence
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue

        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "axon_vertex"),
              let fragment = library.makeFunction(name: "axon_fragment")
        else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            return nil
        }

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(now - lastTime)
        lastTime = now

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        var uniforms = presence.tick(
            dt: dt,
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AxonUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
