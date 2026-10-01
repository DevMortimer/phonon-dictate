import MetalKit
import SwiftUI

/// Voice features for one audio buffer, each 0...1.
struct Meter {
    var level: Float
    var low: Float
    var mid: Float
    var high: Float
}

/// What the ribbon shows. Set on the main queue; the renderer eases toward these targets every frame.
final class RibbonInput {
    var meter = Meter(level: 0, low: 0, mid: 0, high: 0)
    /// 1 pulls every strand into one straight line.
    var flatten: Float = 0
    /// 1 shows a highlight that sweeps along the line.
    var sweep: Float = 0
    /// Breathe without audio (the setup window).
    var synthetic = false

    private(set) var pulse: Float = 0

    /// A short flare, for example when setup completes.
    func excite() { pulse = 1 }

    fileprivate func decayPulse(_ dt: Float) { pulse = max(0, pulse - dt * 0.8) }
}

/// A glowing three-strand ribbon drawn by a Metal fragment shader.
/// Low frequencies swell it, high frequencies ripple it, loudness warms its color.
struct RibbonView: NSViewRepresentable {
    let input: RibbonInput
    var active: Bool

    func makeCoordinator() -> RibbonRenderer { RibbonRenderer(input: input) }

    func makeNSView(context: Context) -> ScaledMTKView {
        let view = ScaledMTKView(frame: .zero, device: RibbonRenderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        view.wantsDrawing = active
        return view
    }

    func updateNSView(_ view: ScaledMTKView, context: Context) {
        view.wantsDrawing = active
    }
}

/// An MTKView that draws only while its window is visible on screen, at the window's scale.
final class ScaledMTKView: MTKView {
    /// The owner wants frames. Drawing also needs a visible window: in a hidden or covered window,
    /// `nextDrawable` blocks the main thread for up to a second per frame.
    var wantsDrawing = false {
        didSet { updatePaused() }
    }
    private var occlusionObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = window.map {
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: $0,
                                                   queue: .main) { [weak self] _ in self?.updatePaused() }
        }
        syncScale()
        updatePaused()
    }

    private func updatePaused() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        isPaused = !(wantsDrawing && visible)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncScale()
    }

    private func syncScale() {
        guard let scale = window?.backingScaleFactor else { return }
        layer?.contentsScale = scale
    }
}

final class RibbonRenderer: NSObject, MTKViewDelegate {
    static let device = MTLCreateSystemDefaultDevice()

    private static let pipeline: MTLRenderPipelineState? = {
        guard let device else { return nil }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "ribbon_vertex")
            desc.fragmentFunction = library.makeFunction(name: "ribbon_fragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("PhononDictate: ribbon shader failed: \(error)")
            return nil
        }
    }()

    private struct Uniforms {
        var time: Float, width: Float, height: Float, scale: Float
        var level: Float, low: Float, mid: Float, high: Float
        var flatten: Float, sweep: Float, sweepPhase: Float
    }

    private let input: RibbonInput
    private let queue = RibbonRenderer.device?.makeCommandQueue()
    private let start = CACurrentMediaTime()
    private var last = CACurrentMediaTime()
    private var u = Uniforms(time: 0, width: 1, height: 1, scale: 2, level: 0, low: 0, mid: 0, high: 0,
                             flatten: 0, sweep: 0, sweepPhase: 0)

    init(input: RibbonInput) {
        self.input = input
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(now - last, 0.05))
        last = now
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        var target = input.meter
        if input.synthetic {
            let t = Float(now - start)
            target = Meter(level: 0.48 + 0.14 * sin(t * 1.3) + 0.06 * sin(t * 3.7),
                           low: 0.5 + 0.3 * sin(t * 0.8), mid: 0.4 + 0.3 * sin(t * 1.1 + 1),
                           high: 0.15 + 0.12 * sin(t * 2.3))
        }
        input.decayPulse(dt)
        target.level = max(target.level, input.pulse)
        target.high = max(target.high, input.pulse * 0.6)

        // Fast attack, slow release: the ribbon jumps with a syllable and settles after it.
        func follow(_ value: inout Float, _ goal: Float, up: Float = 22, down: Float = 5) {
            let k = goal > value ? up : down
            value += (goal - value) * (1 - exp(-k * dt))
        }
        follow(&u.level, target.level)
        follow(&u.low, target.low)
        follow(&u.mid, target.mid)
        follow(&u.high, target.high, up: 30, down: 8)
        follow(&u.flatten, input.flatten, up: 7, down: 7)
        follow(&u.sweep, input.sweep, up: 4, down: 6)

        // Louder speech moves the ribbon faster.
        u.time += dt * (calm ? 0.3 : 0.7 + 1.3 * u.level)
        u.sweepPhase = (u.sweepPhase + dt * 0.75).truncatingRemainder(dividingBy: 1)
        u.width = Float(view.drawableSize.width)
        u.height = Float(view.drawableSize.height)
        u.scale = Float(view.window?.backingScaleFactor ?? 2)

        guard let pipeline = RibbonRenderer.pipeline, let queue,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct U {
        float time, width, height, scale;
        float level, low, mid, high;
        float flatten, sweep, sweepPhase;
    };

    struct VOut { float4 pos [[position]]; float2 uv; };

    vertex VOut ribbon_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(p.x, 1.0 - p.y);
        return o;
    }

    constant float3 kCool[3] = { float3(0.30, 0.80, 1.00), float3(0.56, 0.46, 1.00), float3(1.00, 0.38, 0.74) };
    constant float3 kWarm[3] = { float3(1.00, 0.66, 0.30), float3(1.00, 0.40, 0.46), float3(1.00, 0.84, 0.48) };

    fragment float4 ribbon_fragment(VOut in [[stage_in]], constant U& u [[buffer(0)]]) {
        const float TAU = 6.2831853;
        float x = in.uv.x;
        float y = (in.uv.y - 0.5) * u.height;                 // pixels from the center line
        float env = pow(max(sin(M_PI_F * x), 0.0), 1.5);       // pinch at both ends; pow() of a negative is NaN
        float energy = (0.08 + 0.92 * pow(u.level, 0.75)) * (1.0 - u.flatten);
        float amp = u.height * 0.44 * energy * env;
        float warmth = smoothstep(0.35, 0.95, u.level) * 0.8;
        float t = u.time;

        float3 col = float3(0.0);
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float w = sin(x * (1.6 + 0.5 * fi) * TAU + t * (1.1 + 0.35 * fi) + fi * 2.1) * (0.45 + 0.75 * u.low)
                    + sin(x * (4.2 + 1.1 * fi) * TAU - t * (1.9 + 0.3 * fi) + fi) * (0.18 + 0.60 * u.mid)
                    + sin(x * (11.0 + 2.5 * fi) * TAU + t * (3.6 + 0.8 * fi)) * (0.35 * u.high);
            float yi = amp * w * (1.0 - 0.22 * fi) / 1.4;
            float d = abs(y - yi);
            float core = u.scale * (0.8 + 1.2 * energy);
            float glow = 0.9 * exp(-(d * d) / (2.0 * core * core))
                       + 0.22 * exp(-d / (u.scale * (3.0 + 6.0 * energy)));
            col += mix(kCool[i], kWarm[i], warmth) * glow * (0.45 + 0.55 * env);
        }

        // Transcribing: a bright bead runs along the flattened line.
        float sx = u.sweepPhase * 1.5 - 0.25;
        float bx = (x - sx) / 0.06, by = u.scale * 2.5;
        float bead = exp(-bx * bx) * exp(-(y * y) / (2.0 * by * by));
        col += float3(0.9, 0.94, 1.0) * bead * u.sweep * 1.6;

        col = 1.0 - exp(-col * 1.1);                           // overlaps bloom toward white
        float vfade = 1.0 - smoothstep(0.6, 1.0, abs(y) / (0.5 * u.height));  // no visible box edge
        col *= smoothstep(0.0, 0.08, x) * smoothstep(1.0, 0.92, x) * vfade;
        float a = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
        return float4(col, a);                                 // premultiplied
    }
    """
}
