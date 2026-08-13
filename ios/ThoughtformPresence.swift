import Foundation
import Combine
import simd

enum ThoughtformMode: String, CaseIterable {
    case idle, listen, think, speak

    var weights: SIMD4<Float> {
        switch self {
        case .idle: return SIMD4(1, 0, 0, 0)
        case .listen: return SIMD4(0, 1, 0, 0)
        case .think: return SIMD4(0, 0, 1, 0)
        case .speak: return SIMD4(0, 0, 0, 1)
        }
    }
}

enum AlfredPhase: String {
    case idle, recording, stt, thinking, speaking, done, cancelled

    var mode: ThoughtformMode {
        switch self {
        case .idle, .done: return .idle
        case .recording, .cancelled: return .listen
        case .stt, .thinking: return .think
        case .speaking: return .speak
        }
    }
}

/// GPU uniform block — must match `ThoughtformUniforms` in shaders/thoughtform.metal.
struct ThoughtformUniforms {
    var resolutionTimeAmplitude: SIMD4<Float>
    var weights: SIMD4<Float>
    var bandsProgress: SIMD4<Float>
    var attentionChaosQuality: SIMD4<Float>
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    var colorC: SIMD4<Float>
    var background: SIMD4<Float>
}

enum ThoughtformPalette {
    static let gotham = (
        colorA: SIMD4<Float>(0.349, 0.612, 0.671, 1),
        colorB: SIMD4<Float>(0.600, 0.820, 0.808, 1),
        colorC: SIMD4<Float>(0.929, 0.706, 0.263, 1),
        background: SIMD4<Float>(0.047, 0.063, 0.078, 1)
    )
}

final class ThoughtformPresence: ObservableObject {
    @Published private(set) var mode: ThoughtformMode = .idle

    var quality: Float = 1
    var turnId: String?
    var transcript: String = ""

    private var weights = SIMD4<Float>(1, 0, 0, 0)
    private var amplitude: Float = 0
    private var bands = SIMD3<Float>(repeating: 0)
    private var progress: Float = 0
    private var attention: Float = 0.15
    private var chaos: Float = 0
    private var time: Float = 0

    private var targetAmp: Float = 0
    private var targetBands = SIMD3<Float>(repeating: 0)
    private var targetProgress: Float = 0
    private var targetAttention: Float = 0.15
    private var targetChaos: Float = 0
    private var chaosPulse: Float = 0
    private var palette = ThoughtformPalette.gotham

    func setMode(_ mode: ThoughtformMode) {
        self.mode = mode
        switch mode {
        case .idle:
            targetProgress = 0
            targetChaos = min(targetChaos, 0.12)
            targetAttention = 0.15
        case .listen:
            targetAttention = 0.85
            targetProgress = 0
        case .think:
            targetAttention = 0.55
            targetProgress = max(targetProgress, 0.08)
            targetChaos = max(targetChaos, 0.28)
        case .speak:
            targetAttention = 0.7
            targetProgress = max(targetProgress, 0.35)
            targetChaos = min(targetChaos, 0.25)
        }
    }

    func ingestAlfred(phase: AlfredPhase, turnId: String? = nil, transcript: String? = nil) {
        if let turnId { self.turnId = turnId }
        if let transcript { self.transcript = transcript }
        setMode(phase.mode)
        if phase == .thinking || phase == .stt {
            targetChaos = max(targetChaos, 0.3)
        }
        if phase == .done {
            targetProgress = 0
            chaosPulse = 0
        }
    }

    func ingestArbiterEvent(_ name: String) {
        switch name {
        case "request_received":
            targetProgress = max(targetProgress, 0.05)
            targetChaos = max(targetChaos + 0.08, 0.15)
        case "intent":
            targetProgress = max(targetProgress, 0.12)
            targetChaos = max(targetChaos + 0.05, 0.2)
        case "agent_start", "stream_start":
            targetProgress = max(targetProgress, 0.2)
            targetChaos = max(targetChaos, 0.35)
        case "tool_call":
            chaosPulse = max(chaosPulse, 0.85)
            targetProgress = min(1, targetProgress + 0.04)
        case "text":
            targetProgress = min(1, targetProgress + 0.03)
        case "done":
            targetProgress = 1
            targetChaos *= 0.4
        case "error", "escalation":
            chaosPulse = max(chaosPulse, 0.9)
        default:
            break
        }
    }

    func setAudio(rms: Float, low: Float, mid: Float, high: Float) {
        func unit(_ x: Float) -> Float { min(max(x, 0), 1) }
        targetAmp = unit(rms)
        targetBands = SIMD3(unit(low), unit(mid), unit(high))
    }

    func tick(dt: Float, resolution: SIMD2<Float>) -> ThoughtformUniforms {
        let step = min(max(dt, 0), 0.1)
        time += step

        let target = mode.weights
        let kMode = 1 - exp(-step / 0.22)
        weights += (target - weights) * kMode
        let sum = max(weights.x + weights.y + weights.z + weights.w, 0.0001)
        weights /= sum

        let kAudio = 1 - exp(-step / 0.06)
        amplitude += (targetAmp - amplitude) * kAudio
        bands += (targetBands - bands) * kAudio

        let kPulse = 1 - exp(-step / 0.28)
        chaosPulse += (0 - chaosPulse) * kPulse
        let chaosTarget = min(1, max(targetChaos, chaosPulse))
        let kChaos = 1 - exp(-step / 0.45)
        chaos += (chaosTarget - chaos) * kChaos

        let kProg = 1 - exp(-step / 0.35)
        progress += (targetProgress - progress) * kProg
        let kAttn = 1 - exp(-step / 0.28)
        attention += (targetAttention - attention) * kAttn

        return ThoughtformUniforms(
            resolutionTimeAmplitude: SIMD4(resolution.x, resolution.y, time, amplitude),
            weights: weights,
            bandsProgress: SIMD4(bands.x, bands.y, bands.z, progress),
            attentionChaosQuality: SIMD4(attention, chaos, quality, 0),
            colorA: palette.colorA,
            colorB: palette.colorB,
            colorC: palette.colorC,
            background: palette.background
        )
    }
}
